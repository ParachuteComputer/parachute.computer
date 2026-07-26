**This is the install runbook for AI agents.** It installs the self-hosted
Parachute stack — the hub and a vault — on a fresh machine, headlessly, with no
human at a terminal. Every command here is copy-pasteable and every flag is
load-bearing. It is derived from `e2e/stages.sh` in
[parachute-hub](https://github.com/ParachuteComputer/parachute-hub/blob/main/e2e/stages.sh),
the staged end-to-end suite that installs the hub from npm into a fresh
systemd container and drives the whole setup non-interactively. That suite runs
green on every release, so the sequence below is the one that is actually
proven to work.

This page is served as raw markdown at
**<https://parachute.computer/install.md>** — that is the URL to hand an agent.
If you are a human, [the self-host page](https://parachute.computer/start/) is
the friendlier version of the same thing.

## Read this first — the three ways this goes wrong

Three mistakes account for nearly every failed agent install. Each one is
avoidable in a single decision:

1. **Do not install from a git checkout.** `git clone` + `bun link` is the
   *developer* path — it wires the CLI to a working tree, which may be any
   commit, including an old release candidate. For an install, use npm:
   `bun add -g @openparachute/hub`. See step 2.
2. **Do not let anything prompt.** The setup wizard must be driven entirely by
   flags. Piping answers into it does **not** work. See step 4.
3. **A 401 from the vault means the vault is healthy.** It is auth-gated on
   purpose. Do not treat it as a failure and start "fixing" a working install.
   See step 5.

## Preconditions

- **A machine you have root or `sudo` on.** A fresh Ubuntu or Debian box
  (Hetzner, EC2, DigitalOcean, a VM, a box in a closet) is the tested target;
  macOS works too. RPM distros (Amazon Linux, RHEL) are not supported.
- **[Bun](https://bun.sh) 1.3.0 or later.** Step 1 installs it if it is
  missing. Bun is the only runtime — there is no Node requirement.
- **Outbound HTTPS**, to reach npm and bun.sh.
- **Two free local ports: `1939` (hub) and `1940` (vault).** The hub pins 1939
  with no fallback — if something else holds it, the install fails loudly
  rather than moving. Neither port needs to be open to the internet; on Linux
  the hub is supervised by systemd, on macOS by launchd.
- **Ports 80 and 443 open** only if you intend to expose the hub publicly
  (step 6). A loopback-only install needs no inbound ports at all.
- **Decide two values before you start**: the admin username and a strong admin
  password. Generate the password, record it where the person who asked for
  this install will find it, and keep it out of shell history.

## 1. Install Bun

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
command -v bun >/dev/null || curl -fsSL https://bun.sh/install | bash
hash -r
bun --version
```

`bun --version` must print `1.3.0` or higher. On older Bun you may see cosmetic
`InvalidPackageResolution` or `FileNotFound` warnings during the next step; run
`bun upgrade` to clear them.

Add `export PATH="$HOME/.bun/bin:$PATH"` to the shell profile of whoever will
run `parachute` later, or the binary will vanish on the next login.

## 2. Install the hub from npm

```bash
bun add -g @openparachute/hub
hash -r
command -v parachute && parachute --version
```

This is the whole install. `@openparachute/hub` ships the `parachute` binary,
and the binary is the front door to everything else.

**Do not `git clone` the repo and `bun link` it.** That is how contributors run
the hub from a working tree, and it is the single most common way an agent
install goes wrong: the linked binary follows whatever commit is checked out —
frequently a stale release candidate — and `parachute status` will then report
`bun-linked → …` instead of a released version. If you see `bun-linked` in the
`SOURCE` column of `parachute status` on a machine you were asked to *install*,
you took the wrong path.

Check the output of `bun add -g` for a line reading `Blocked N postinstall`. If
it appears, Bun refused to run a package's postinstall and the install is
silently broken — re-run it, do not proceed.

## 3. Bring the hub up (non-interactive)

```bash
parachute init --expose none --no-expose-prompt --no-browser
```

All three flags are required for a headless run, and each one exists because
the interactive path blocks without it:

| Flag | Why |
|---|---|
| `--expose none` | Stay loopback-only. Public exposure is a separate, later decision (step 6). |
| `--no-expose-prompt` | Never block on the interactive "how do you want to reach this?" question. Without it, `init` asks — and on a server it *defaults to Cloudflare*, so an unattended run can wander into a tunnel setup you did not ask for. |
| `--no-browser` | Do not shell out to `open` / `xdg-open`. Print the URL and exit 0. |

`parachute init` is idempotent — re-running it is always safe.

What it does: installs and starts the hub as a managed unit (systemd on Linux,
launchd on macOS) so it survives reboots, installs the **vault module**, and
prints the admin URL. Note the distinction that trips agents up: `init`
installs the vault *module*; it does not create a vault *instance*. The wizard
in the next step does that.

Optional flags worth knowing:

- `--channel rc` — install modules from the `rc` dist-tag instead of `latest`.
  Only use this if you were explicitly asked to track release candidates.
- `--hub-origin https://host.example.com` — persist the canonical public origin
  (the OAuth issuer) *before* the modules start, so they come up accepting it
  in one pass. This is for reverse-proxy / Caddy-direct boxes that bind
  loopback but are reached over a public HTTPS URL. Skip it for a loopback
  install.

## 4. Drive the setup wizard with flags — never interactively

```bash
parachute setup-wizard \
  --hub-url http://127.0.0.1:1939 \
  --account-username "$PARACHUTE_ADMIN_USER" \
  --account-password "$PARACHUTE_ADMIN_PASS" \
  --vault-mode create \
  --vault-name default \
  --transcribe-mode none \
  --expose-mode localhost
```

This is the same three-step flow the browser wizard walks — account, vault,
expose — hitting the same backend handlers, in your terminal. When it finishes
it prints `Setup complete`, and along the way `admin account created` and
`Vault ready`. Assert on those lines; do not assume.

**Supply every flag. Do not pipe answers in.** The wizard's prompts are
readline-backed, and on a non-interactive stdin — a cloud-init script, an
`ssh host '…'` one-liner, a CI container, a subprocess spawned by an agent —
piped input is not read as an answer. Hub **0.7.7 and later** fails fast with a
message naming the flag that would have answered the prompt, instead of
hanging. Older hubs hang forever. Flags are the sanctioned path; piped stdin is
not a path at all.

Notes on the flags:

- `--hub-url http://127.0.0.1:1939` — **run this on the box, against
  loopback.** A loopback caller already proves on-box access, so the hub hands
  it the one-time bootstrap token transparently. Drive the wizard from *off*
  the box and you must pass `--bootstrap-token <token>` as well.
- `--vault-mode` accepts `create`, `import`, or `skip`. Use `create` with
  `--vault-name` for a new vault. `default` is the conventional name and the
  one every client example assumes; use it unless you were told otherwise.
  Vault names are lowercase alphanumeric plus hyphens/underscores, 2–32
  characters. To seed from an existing git repo of markdown instead:
  `--vault-mode import --vault-import-url <url>` (add `--vault-import-pat` for
  a private repo).
- `--transcribe-mode` accepts `none`, `local`, `groq`, or `openai`. **Use
  `none`.** Transcription is optional, and the module behind it is deprecated —
  see "Known gaps" below.
- `--expose-mode` accepts `localhost`, `tailnet`, or `public`. Use `localhost`
  here and handle exposure deliberately in step 6.

The password appears in the process table and in shell history. Put it in an
environment variable read from a file with `0600` permissions rather than
typing it inline, and clear the variable afterward. On a box you are building
from a container image or cloud-init, the alternative is to seed the admin at
first boot with `PARACHUTE_INITIAL_ADMIN_USERNAME` and
`PARACHUTE_INITIAL_ADMIN_PASSWORD` — set before the hub ever starts, they
create the admin without the wizard's account step.

Re-running the wizard is safe: it picks up at the next undone step and skips
completed ones without prompting.

## 5. Verify — you are done when

Run all five. Every one must match. Do not report success on fewer.

**The hub unit is running** (Linux; on macOS use `parachute status` instead):

```bash
systemctl is-active parachute-hub.service
```

→ `active`

**The hub is healthy and its database is open:**

```bash
curl -fsS http://127.0.0.1:1939/health
```

→ a JSON body containing `"status":"ok"` **and** `"db":"ok"`, e.g.
`{"status":"ok","service":"parachute-hub","version":"…","db":"ok","instance":"…"}`.
The `db` field is the one that matters — a hub can answer while its database
handle is dead, and `"db":"ok"` is what rules that out. Poll for up to 30
seconds after `init`; it is not instant.

**The vault is up and correctly refusing anonymous callers:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:1939/vault/default/health
```

→ `401`

**`401` is the healthy answer.** The vault is auth-gated; an unauthenticated
probe getting 401 proves it is serving *and* enforcing auth. `200` is also
acceptable. Anything in the 5xx range, or `000` (connection refused), is a real
failure. If your check treats non-2xx as failure, fix the check, not the
install.

**The vault shows as active without any manual start:**

```bash
parachute status
```

→ a table with columns `SERVICE PORT VERSION STATE PID UPTIME LATENCY SOURCE`,
with a `parachute-vault` row on port `1940` in state `active`, and a
`parachute-hub (internal)` row on port `1939`. You should **not** need to run
`parachute start vault` or restart the hub to get there — the wizard's create
path starts the vault itself. If the vault is stuck `inactive`, something is
wrong; do not paper over it with a restart.

**A minted token can read the vault over REST:**

```bash
TOKEN="$(parachute auth mint-token --scope vault:default:read | tail -n1)"
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:1939/vault/default/api/notes
```

→ `200`

This is the end-to-end proof: identity, authorization, routing, and the vault's
data plane all working together. If the first four checks pass and this one
does not, the problem is auth, not the install.

## 6. Optional: reach it from the internet

A loopback install is complete and usable by anything running on the same box.
Exposure is what lets a phone, a browser elsewhere, or a hosted AI reach it.
Skip this section unless you were asked for it. There are three routes.

**Caddy-direct, on a fresh Ubuntu/Debian box with a public IP.** The site ships
a script that does hub + vault + Caddy + a real Let's Encrypt certificate in
one pass:

```bash
curl -fsSL https://parachute.computer/install/server.sh | bash
```

It is fully non-interactive and it replaces steps 1–3 above. With no domain you
get working HTTPS at `https://<your-ip>.sslip.io`; set
`PARACHUTE_DOMAIN=vault.example.com` (with an A record already pointing at the
box) to use your own. **It stops where an agent cannot follow**: it prints a
one-time bootstrap token and tells a human to open the setup URL in a browser.
Finish it headlessly by running step 4 on the box, against loopback, with
`--expose-mode public`.

**Cloudflare Tunnel**, on your own domain whose apex is already a Cloudflare
zone (the free tier is fine — `expose` creates the tunnel for you). Install the
static binary; distro packages are unreliable:

```bash
case "$(uname -m)" in
  x86_64|amd64)  CF_ARCH=amd64 ;;
  aarch64|arm64) CF_ARCH=arm64 ;;
  armv7l|armhf)  CF_ARCH=arm ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
curl -fsSL -o /usr/local/bin/cloudflared \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
chmod +x /usr/local/bin/cloudflared
parachute expose public --cloudflare --domain vault.example.com
```

`expose` waits for the connector to connect before reporting success — look for
`Cloudflare tunnel up` and `Connector connected` in its output, then confirm
`https://vault.example.com/health` returns `"db":"ok"`. Tear it down with
`parachute expose public off --cloudflare`; that stops the local connector but
leaves the tunnel defined in your Cloudflare account, so delete it there too if
this was temporary.

**Tailscale**, for a private `*.ts.net` address across your own tailnet:
`parachute expose tailnet`. Requires Tailscale 1.82+ installed with
`tailscale up` already run.

After any exposure change, re-point MCP clients at the new origin — the OAuth
issuer moves with it.

## 7. Connect an AI

One URL does it:

```
<hub-origin>/vault/<vault-name>/mcp
```

`<hub-origin>` is the address the hub answers on — `http://127.0.0.1:1939` for
a loopback install, your public HTTPS origin after step 6. It is **not** the
vault's own port 1940; the vault is reached *through* the hub. `<vault-name>`
is what you passed to `--vault-name` (`default` if you followed this runbook).
The `/mcp` suffix is required.

**OAuth happens on first use.** An OAuth-capable client registers itself, sends
the user to the hub to sign in and approve, and receives a token — nothing to
configure ahead of time. For Claude Code:

```bash
claude mcp add --transport http parachute-default http://127.0.0.1:1939/vault/default/mcp
```

Then start a new session (MCP config loads at session start) and run `/mcp` to
confirm the vault's tools are present.

For a client that cannot do the browser OAuth flow — a headless box, a daemon —
mint a bearer token instead and send it as an `Authorization: Bearer` header
alongside the same URL:

```bash
parachute auth mint-token --scope vault:default:write
```

To look at the vault without installing anything, open
[my.parachute.computer](https://my.parachute.computer) and give it
`<hub-origin>/vault/<vault-name>`. The app runs in the browser; the notes never
leave the hub.

## Known gaps — stated honestly

These are current, real, and will waste your time if you discover them the hard
way.

**`parachute install app` may fail with a 404 — check before you rely on it.**
The hub resolves the short name `app` to `@openparachute/app` and runs
`bun add -g` against it. That package is being published, so verify rather than
assume:

```sh
npm view @openparachute/app version
```

If that 404s, the package is not on npm yet and `parachute install app` will
fail — no flag fixes it. Two paths that work either way: build from source
([ParachuteComputer/parachute-app](https://github.com/ParachuteComputer/parachute-app)),
or skip installing a UI entirely and use
[my.parachute.computer](https://my.parachute.computer) — a browser app that
talks to any vault, so it needs nothing on the box.

**Do not install scribe.** `@openparachute/scribe`, the standalone
transcription module, was deprecated on 2026-07-24. Its capability is folding
into the vault. Existing installs keep running; new ones should not be created.
This is why step 4 passes `--transcribe-mode none`, and why you should ignore
any prompt or document that suggests `parachute install scribe`.

**Modules that *are* published and installable**, if you were asked for them:
`parachute install vault` (`@openparachute/vault`, which `parachute init`
already installs) and `parachute install surface` (`@openparachute/surface` —
the UI host). Confirm before installing anything else:

```bash
npm view @openparachute/<name> version
```

A 404 there means the module is not installable today, whatever the CLI's
service list says.

## Troubleshooting

**The wizard hangs, or exits with "stdin is not interactive".** You did not
supply every flag it needed. The error message names the flag that would have
answered the prompt — pass it and re-run. Piping answers in will not help; see
step 4. On hub versions before 0.7.7 there is no error, just a hang — upgrade.

**The vault "fails" its health check with 401.** It did not fail. 401 is the
healthy response for an auth-gated vault. See step 5.

**`parachute init` fails because port 1939 is in use.** The hub pins 1939 with
no fallback, deliberately: exposure targets are composed as
`http://127.0.0.1:1939/` and that address has to be stable across machines.
Find the holder with `lsof -i :1939` (or `ss -lptn 'sport = :1939'`) and free
it. On macOS, a container runtime such as OrbStack can shadow loopback ports —
check there before assuming the port is free. If the vault's port 1940 is
taken, the same applies: free it rather than working around it.

**`parachute status` says `bun-linked → …` on a fresh install.** You installed
from a git checkout instead of npm. See step 2. Remove the link and
`bun add -g @openparachute/hub`.

**A client cannot reach the MCP endpoint.** Confirm the URL ends in `/mcp`,
points at the *hub* origin rather than port 1940, and carries the right vault
name. If the hub is behind a Cloudflare tunnel and OAuth consent succeeds but
the client is then rejected, that is Cloudflare's Bot Fight Mode / Browser
Integrity Check challenging the server-to-server token exchange, not a
Parachute bug — the fix is a WAF skip rule for the exposed hostname, and it is
[written up in full on the self-host page](https://parachute.computer/start/#connect-mcp-clients).

## The whole thing, as one script

For a fresh Ubuntu/Debian box, loopback-only, run as root. Set the two
variables at the top and paste the rest.

```bash
#!/usr/bin/env bash
set -euo pipefail

PARACHUTE_ADMIN_USER="owner"
PARACHUTE_ADMIN_PASS="<a strong password you generated and recorded>"
VAULT_NAME="default"
HUB="http://127.0.0.1:1939"

# 1. bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
command -v bun >/dev/null || curl -fsSL https://bun.sh/install | bash
hash -r

# 2. hub, from npm
bun add -g @openparachute/hub
hash -r
parachute --version

# 3. hub up, nothing interactive
parachute init --expose none --no-expose-prompt --no-browser

# wait for the hub's database to be genuinely open
for _ in $(seq 1 30); do
  if curl -fsS "$HUB/health" 2>/dev/null | grep -q '"db":"ok"'; then break; fi
  sleep 1
done
curl -fsS "$HUB/health" | grep -q '"db":"ok"'

# 4. setup, entirely by flags
parachute setup-wizard \
  --hub-url "$HUB" \
  --account-username "$PARACHUTE_ADMIN_USER" \
  --account-password "$PARACHUTE_ADMIN_PASS" \
  --vault-mode create \
  --vault-name "$VAULT_NAME" \
  --transcribe-mode none \
  --expose-mode localhost

# 5. verify — 401 from the vault is HEALTHY
code=""
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$HUB/vault/$VAULT_NAME/health" || true)"
  case "$code" in 401|200) break ;; esac
  sleep 1
done
case "$code" in
  401|200) ;;
  *) echo "vault not reachable (HTTP $code)" >&2; exit 1 ;;
esac

parachute status || true
TOKEN="$(parachute auth mint-token --scope "vault:$VAULT_NAME:read" | tail -n1)"
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" \
     "$HUB/vault/$VAULT_NAME/api/notes")" = "200" ]

echo "Parachute is up. MCP endpoint: $HUB/vault/$VAULT_NAME/mcp"
```

## Housekeeping

- **Upgrade everything**: `parachute upgrade` sweeps the hub and every installed
  module to the latest release; vault migrations run automatically on the first
  post-upgrade boot.
- **Logs**: `parachute logs vault -f` (or `hub`, `surface`).
- **Lifecycle**: `parachute start|stop|restart <service>` — short service names
  (`vault`, not `parachute-vault`).
- **Health triage**: `parachute doctor` runs the checks and names the one thing
  to fix.
- **Backup**: `parachute-vault export <dir>` writes the whole vault to portable
  markdown; `import` reads it back. Everything is plain files — leaving is a
  copy, not a migration.
- **Config lives in `~/.parachute/`** (override with `PARACHUTE_HOME`), with
  per-module directories beneath it.

## Where this came from

Every command above is either taken directly from
[`e2e/stages.sh`](https://github.com/ParachuteComputer/parachute-hub/blob/main/e2e/stages.sh)
— the staged end-to-end suite that installs the hub from npm into a fresh
systemd container and drives setup entirely by flags, and which gates every
release — or verified against the `parachute` CLI's own source and help output.
Nothing here is aspirational. If a command in this runbook does not work,
that is a bug worth
[reporting](https://github.com/ParachuteComputer/parachute-hub/issues).
