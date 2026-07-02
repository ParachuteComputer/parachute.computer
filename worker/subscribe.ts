// worker/subscribe.ts — standalone Cloudflare Worker for the Parachute
// interest list (issue #25).
//
// Deployed separately from the GitHub-Pages-hosted static site, at its own
// origin (default: https://subscribe.parachute.computer/). The homepage form
// does a NATIVE cross-origin `<form method="POST">` to this Worker, which
// validates + normalizes the email, inserts a row into the D1 `interests`
// table, then 303-redirects the browser back to the static site.
//
// Why a Worker (not a Pages Function): we're keeping the site on GitHub
// Pages (no apex DNS migration). The backend is the only piece that needs
// Cloudflare, so it lives as a small standalone Worker + D1.
//
// Why NO CORS is needed: a native browser form POST is a "simple request"
// and the response is a 303 redirect the browser follows on its own. The
// page never reads the cross-origin response with JS, so there's no
// preflight and no CORS headers required. (This is the whole reason the
// form is plain HTML, not a fetch().)
//
// The redirect targets are ABSOLUTE site URLs because this Worker is a
// different origin from the site — a relative Location would resolve
// against the Worker origin, not parachute.computer.
//
// V1 deliberately does not:
//   - de-dupe on email (duplicate signups preserve signal)
//   - send a confirmation email (no Resend yet — V2)
//   - link to a user account (no user store yet — V3)
//   - rate-limit (known simple-start gap; see note below)
// Two reserved columns on the table (`user_id`, `resend_contact_id`) keep
// the door open for those without a future migration.

interface Env {
  DB: D1Database;
}

// Permissive but reasonable email check. The goal is to catch obvious
// typos (missing @, runaway length), not to be RFC 5322 compliant. D1 is
// the source of truth — anything that gets in here that turns out to be
// junk is filtered downstream.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LEN = 254;

// Absolute site URLs — the Worker is a different origin from the site.
const SITE_ORIGIN = "https://parachute.computer";
const REDIRECT_THANKS = `${SITE_ORIGIN}/subscribe/thanks/`;
const REDIRECT_ERROR = `${SITE_ORIGIN}/?subscribe_error=1`;

function redirect(location: string): Response {
  // 303 See Other — correct for a POST → GET handoff. Browsers will GET
  // the redirect target rather than re-POSTing.
  return new Response(null, {
    status: 303,
    headers: { Location: location },
  });
}

function sourcePathFromReferer(referer: string | null): string | null {
  if (!referer) return null;
  try {
    return new URL(referer).pathname || null;
  } catch {
    return null;
  }
}

// Optional "what do you take notes in today?" answer from the landing form.
// Whitelisted to a known set so the column stays clean; anything unexpected
// is dropped to NULL rather than stored as junk.
const NOTES_APP_VALUES = new Set([
  "apple-notes",
  "notion",
  "obsidian",
  "paper",
  "nothing",
]);

interface Submission {
  email: string;
  notesApp: string | null;
}

async function readSubmission(request: Request): Promise<Submission> {
  // Accept both standard form-encoded posts (default browser form
  // behavior, no JS required) and JSON in case anyone POSTs from a
  // script. The body can only be read once, so pull every field here.
  const contentType = request.headers.get("Content-Type") || "";
  let email = "";
  let notesAppRaw = "";
  if (contentType.includes("application/json")) {
    const body = (await request.json().catch(() => ({}))) as {
      email?: unknown;
      notes_app?: unknown;
    };
    email = typeof body.email === "string" ? body.email : "";
    notesAppRaw = typeof body.notes_app === "string" ? body.notes_app : "";
  } else {
    const form = await request.formData();
    const e = form.get("email");
    const n = form.get("notes_app");
    email = typeof e === "string" ? e : "";
    notesAppRaw = typeof n === "string" ? n : "";
  }
  const notesApp = NOTES_APP_VALUES.has(notesAppRaw.trim().toLowerCase())
    ? notesAppRaw.trim().toLowerCase()
    : null;
  return { email, notesApp };
}

async function handleSubscribe(request: Request, env: Env): Promise<Response> {
  let submission: Submission;
  try {
    submission = await readSubmission(request);
  } catch {
    return redirect(REDIRECT_ERROR);
  }

  const email = submission.email.trim().toLowerCase();
  if (!email || email.length > MAX_EMAIL_LEN || !EMAIL_RE.test(email)) {
    return redirect(REDIRECT_ERROR);
  }

  const sourcePath = sourcePathFromReferer(request.headers.get("Referer"));

  try {
    await env.DB.prepare(
      "INSERT INTO interests (email, source_path, notes_app) VALUES (?, ?, ?)"
    )
      .bind(email, sourcePath, submission.notesApp)
      .run();
  } catch (err) {
    // Log to Cloudflare logs but don't surface DB internals to the user.
    console.error("[subscribe] insert failed:", err);
    return redirect(REDIRECT_ERROR);
  }

  return redirect(REDIRECT_THANKS);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "POST") {
      return handleSubscribe(request, env);
    }

    // Optional GET health check — handy for smoke-testing the deploy
    // without writing a row. Returns 200 so `curl <worker-url>` confirms
    // the Worker is live and bound.
    if (request.method === "GET") {
      return new Response("ok — POST an email field to subscribe\n", {
        status: 200,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    // Reject other methods so a stray verb doesn't behave ambiguously.
    return new Response(`Method ${request.method} not allowed`, {
      status: 405,
      headers: { Allow: "POST, GET" },
    });
  },
};
