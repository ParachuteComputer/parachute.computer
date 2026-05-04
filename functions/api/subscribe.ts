// /api/subscribe — Cloudflare Pages Function
//
// V1 of the Parachute interest list (issue #25). Accepts a POST from the
// homepage email form, validates + normalizes the email, inserts a row
// into the D1 `interests` table, and redirects to /subscribe/thanks/.
//
// Reference pattern: LVB's `/api/interests` route (Hono on Workers). This
// is the Pages Functions equivalent — no Hono, just the Pages Functions
// `onRequestPost` handler.
//
// V1 deliberately does not:
//   - de-dupe on email (duplicate signups preserve signal)
//   - send a confirmation email (no Resend yet — V2)
//   - link to a user account (no user store yet — V3)
// Two reserved columns on the table (`user_id`, `resend_contact_id`) keep
// the door open for those without a future migration.
//
// CORS: not needed. Same-origin POST from the parachute.computer form to
// a Pages Function on the same Pages project.

interface Env {
  DB: D1Database;
}

// Permissive but reasonable email check. Mirrors LVB: the goal is to
// catch obvious typos (missing @, runaway length), not to be RFC 5322
// compliant. D1 is the source of truth — anything that gets in here that
// turns out to be junk is filtered downstream.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LEN = 254;

const REDIRECT_THANKS = "/subscribe/thanks/";
const REDIRECT_ERROR = "/?subscribe_error=1";

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

async function readEmail(request: Request): Promise<string> {
  // Accept both standard form-encoded posts (default browser form
  // behavior, no JS required) and JSON in case anyone POSTs from a
  // script. Keep this simple — one input field.
  const contentType = request.headers.get("Content-Type") || "";
  if (contentType.includes("application/json")) {
    const body = (await request.json().catch(() => ({}))) as { email?: unknown };
    return typeof body.email === "string" ? body.email : "";
  }
  const form = await request.formData();
  const value = form.get("email");
  return typeof value === "string" ? value : "";
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  let raw: string;
  try {
    raw = await readEmail(request);
  } catch {
    return redirect(REDIRECT_ERROR);
  }

  const email = raw.trim().toLowerCase();
  if (!email || email.length > MAX_EMAIL_LEN || !EMAIL_RE.test(email)) {
    return redirect(REDIRECT_ERROR);
  }

  const sourcePath = sourcePathFromReferer(request.headers.get("Referer"));

  try {
    await env.DB.prepare(
      "INSERT INTO interests (email, source_path) VALUES (?, ?)"
    )
      .bind(email, sourcePath)
      .run();
  } catch (err) {
    // Log to Cloudflare logs but don't surface DB internals to the user.
    console.error("[subscribe] insert failed:", err);
    return redirect(REDIRECT_ERROR);
  }

  return redirect(REDIRECT_THANKS);
};

// Reject other methods so a stray GET doesn't 404 ambiguously.
export const onRequest: PagesFunction<Env> = async ({ request }) => {
  return new Response(`Method ${request.method} not allowed`, {
    status: 405,
    headers: { Allow: "POST" },
  });
};
