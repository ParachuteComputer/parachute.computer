#!/usr/bin/env bash
#
# Parachute — DigitalOcean (and any fresh Ubuntu box) ZERO-SSH setup.
#
#   curl -fsSL https://parachute.computer/install/digitalocean.sh | bash
#
# Render-like experience: create a droplet, paste ONE cloud-init User Data block
# (optionally your domain), wait ~2-3 min, then set your admin password IN THE
# BROWSER via a one-time bootstrap token. No credentials live in the cloud config.
#
# What it does, on a fresh Ubuntu 24.04 droplet (run as root, or a sudo user):
#   1. Installs Bun (the JS runtime Parachute is built on) + @openparachute/hub
#      and @openparachute/vault globally.
#   2. Derives a PUBLIC HTTPS hostname with no DNS setup needed:
#        • PARACHUTE_DOMAIN if you set one (point an A-record at the droplet IP),
#        • else <droplet-ip>.sslip.io (wildcard DNS → the IP — zero config).
#   3. `parachute init --hub-origin https://<hostname>` — persists the canonical
#      public origin to the hub DB BEFORE modules spawn, so vault (and scribe)
#      come up accepting it in one pass. Starts hub + vault. No tunnel.
#   4. Installs + configures Caddy as the TLS terminator: it provisions a Let's
#      Encrypt cert for <hostname> and reverse-proxies HTTPS → the loopback hub.
#      Caddy strips client-supplied trust-signal headers (defense-in-depth — it's
#      the trusted edge now).
#   5. Surfaces the hub's one-time BOOTSTRAP TOKEN: on a fresh box with no admin,
#      `parachute serve` mints an in-memory `parachute-bootstrap-<rand>` token.
#      We read it from the loopback hub and write it + the /admin/setup URL into
#      /root/parachute-setup.txt. The operator opens /admin/setup in their
#      browser, pastes the token, and chooses their own username + password —
#      so the password is NEVER stored in the cloud config, console, or metadata.
#   6. Decides transcription by RAM (non-fatal): ≥2 GB → optionally install the
#      local Scribe engine; smaller boxes → steer to a cloud provider or none.
#
# Idempotent — safe to re-run. Each step skips itself if already done.
#
# ─────────────────────────────────────────────────────────────────────────────
# User Data (cloud-init) — paste this into the droplet's "User Data" field.
# A plain `#!/bin/bash` script runs as ONE shell on first boot, so the exports
# below reach the piped install script's environment (a `#cloud-config` runcmd
# list would run each line as a SEPARATE shell — exports would NOT carry over).
#
#   #!/bin/bash
#   # export PARACHUTE_DOMAIN="vault.example.com"   # optional; else <ip>.sslip.io
#   curl -fsSL https://parachute.computer/install/digitalocean.sh | bash
#
# Security win: NO admin username/password in User Data. You set your password in
# the BROWSER at /admin/setup using a one-time bootstrap token read from the box.
# Nothing sensitive persists in DO's User Data, droplet console, or metadata.
# ─────────────────────────────────────────────────────────────────────────────
#
# Recognized environment variables (all optional):
#   PARACHUTE_DOMAIN           public hostname (A-record → droplet IP). Omit for sslip.io.
#   PARACHUTE_TRANSCRIBE       local | cloud | none. Default: auto by RAM.
#   PARACHUTE_HUB_PORT         hub port (default 1939).
#   PARACHUTE_CHANNEL          npm dist-tag: latest | rc. Default: rc during the
#                              pre-1.0 soak — the zero-SSH Caddy stack ships on
#                              `rc` first, so the plain one-liner just works. Set
#                              `PARACHUTE_CHANNEL=latest` to pin the last stable.
#
# ─────────────────────────────────────────────────────────────────────────────
# Droplet sizing
#   $6/mo  (1 GB / 1 vCPU)  — hub + vault. Cloud transcription (Groq) or none.
#   $12/mo (2 GB / 1 vCPU)  — pick this for on-box local transcription (Scribe),
#                             or to run Claude Code on the box.
#   Image: Ubuntu 24.04 LTS x64. Ports 80 + 443 must be reachable (DO droplets
#   have no firewall by default — fine; if you enabled ufw, open 80 + 443).
# ─────────────────────────────────────────────────────────────────────────────
#
# This script touches only your own box. It installs nothing Parachute-operated
# between you and your data — everything lands under ~/.parachute/ on your disk.

set -euo pipefail

# cloud-init's scripts_user stage runs as root with a MINIMAL environment —
# notably no $HOME. Default it before anything below dereferences $HOME under
# `set -u` (the Bun install dir, the ~/.bashrc PATH line, the setup-summary
# path) — an unset $HOME there is what aborted the first unattended run. A sudo
# caller already has $HOME set, so this is a no-op for the interactive path.
export HOME="${HOME:-/root}"

# ── pretty output ────────────────────────────────────────────────────────────
BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; BLUE="$(printf '\033[34m')"
# Disable color if stdout isn't a terminal (e.g. piped to a log).
if [ ! -t 1 ]; then BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; BLUE=""; fi

step() { printf "\n%s==>%s %s%s%s\n" "$BLUE" "$RESET" "$BOLD" "$1" "$RESET"; }
info() { printf "    %s\n" "$1"; }
ok()   { printf "    %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "    %s!%s %s\n" "$YELLOW" "$RESET" "$1"; }

# ── 0. sanity: Linux only ────────────────────────────────────────────────────
if [ "$(uname -s)" != "Linux" ]; then
  echo "This script targets a fresh Ubuntu/Linux server (e.g. a DigitalOcean droplet)."
  echo "On macOS or your laptop, follow https://parachute.computer/start/ instead."
  exit 1
fi

# `sudo` only if we're not already root. On a fresh DO droplet you're root and
# sudo may not be installed — so resolve a runner that works either way.
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  echo "Run this as root, or install sudo first (this droplet has neither)."
  exit 1
fi

printf "\n%sParachute — DigitalOcean / Ubuntu zero-SSH setup%s\n" "$BOLD" "$RESET"
printf "%shub + vault + public HTTPS (Caddy), in one command%s\n" "$DIM" "$RESET"

# ── 1. base packages (curl, unzip — Bun's installer needs unzip) ─────────────
# apt wrapper that survives cloud-init's early boot. On first boot, cloud-init's
# own apt run (and unattended-upgrades) often hold the dpkg/apt locks for a
# minute or two. `DPkg::Lock::Timeout=120` makes apt WAIT for the lock instead
# of failing instantly with "Could not get lock" — the single most common
# unattended-install failure. DEBIAN_FRONTEND=noninteractive avoids tzdata-style
# dialogs (there's no TTY under cloud-init). -y answers prompts automatically.
apt_get() {
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 "$@"
}

step "Checking base packages (curl, unzip, ca-certificates)"
NEED_PKGS=""
command -v curl  >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS curl"
command -v unzip >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS unzip"
# ca-certificates is needed for HTTPS metadata fetch + apt over https (Caddy repo).
[ -f /etc/ssl/certs/ca-certificates.crt ] || NEED_PKGS="$NEED_PKGS ca-certificates"
if [ -n "$NEED_PKGS" ]; then
  info "Installing:$NEED_PKGS"
  apt_get update -qq
  # shellcheck disable=SC2086  # intentional word-split: pass each package as its own arg
  apt_get install -y -qq $NEED_PKGS
  ok "Base packages installed"
else
  ok "curl + unzip + ca-certificates already present"
fi

# ── 2. Bun ───────────────────────────────────────────────────────────────────
# Parachute needs Bun 1.3+. The official installer is idempotent — re-running it
# just refreshes to the latest. We put ~/.bun/bin on PATH for THIS shell so the
# rest of the script can call `bun`/`parachute` without a re-login.
step "Installing Bun (JS runtime)"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
if command -v bun >/dev/null 2>&1; then
  ok "Bun already installed ($(bun --version))"
else
  curl -fsSL https://bun.sh/install | bash
  ok "Bun installed"
fi
# Ensure ~/.bun/bin is on PATH for the remainder of this script.
case ":$PATH:" in
  *":$BUN_INSTALL/bin:"*) : ;;
  *) export PATH="$BUN_INSTALL/bin:$PATH" ;;
esac

# Persist PATH for future logins, if the installer didn't already (idempotent —
# we only append the line if it's not present). Covers bash + a common interactive shell.
# shellcheck disable=SC2016  # literal: this string is WRITTEN to an rc file, expanded at login
BUN_PATH_LINE='export PATH="$HOME/.bun/bin:$PATH"'
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  # Match the literal `.bun/bin` substring — bun's own installer and the line we
  # append both contain it (written as $HOME/$BUN_INSTALL tokens, not expanded),
  # so this stays idempotent across re-runs instead of double-appending.
  if [ -f "$rc" ] && ! grep -qF '.bun/bin' "$rc" 2>/dev/null; then
    printf '\n# Added by Parachute setup\n%s\n' "$BUN_PATH_LINE" >> "$rc"
  fi
done

# Verify Bun is callable now.
if ! command -v bun >/dev/null 2>&1; then
  echo "Bun installed but not on PATH. Open a fresh shell and re-run this script."
  exit 1
fi
BUN_VER="$(bun --version)"
info "Bun version: $BUN_VER"
# Soft warning if older than 1.3 (Parachute wants 1.3+). We don't hard-fail —
# the installer fetches latest, so this should only trip on a pre-seeded box.
case "$BUN_VER" in
  0.*|1.0.*|1.1.*|1.2.*) warn "Bun $BUN_VER is older than 1.3 — Parachute wants 1.3+. Consider: bun upgrade" ;;
esac

# ── 3. Parachute: hub + vault ────────────────────────────────────────────────
# `bun add -g` installs the global packages. `parachute init` (below) also
# installs the vault — we add the vault explicitly too so a re-run stays whole.
# CHANNEL pins the npm dist-tag (latest|rc). Default `rc` during the pre-1.0
# soak — the zero-SSH Caddy stack ships on `rc` first, so the plain one-liner
# works without any override; set PARACHUTE_CHANNEL=latest to pin the last
# stable. Resolved once here and reused for the optional scribe install below.
CHANNEL="${PARACHUTE_CHANNEL:-rc}"
step "Installing Parachute (hub + vault, channel: ${CHANNEL})"
bun add -g "@openparachute/hub@${CHANNEL}" "@openparachute/vault@${CHANNEL}"
ok "@openparachute/hub + @openparachute/vault installed (${CHANNEL})"

if ! command -v parachute >/dev/null 2>&1; then
  echo "The 'parachute' binary isn't on PATH after install. Open a fresh shell"
  echo "(so ~/.bun/bin is picked up) and re-run, or run: export PATH=\"\$HOME/.bun/bin:\$PATH\""
  exit 1
fi

# ── 4. derive the public hostname ────────────────────────────────────────────
# Two ways, no DNS console step required from the operator:
#   • PARACHUTE_DOMAIN — bring your own (you've pointed an A-record at the IP).
#     Sturdier for production: it has its own Let's Encrypt registered-domain
#     rate-limit budget.
#   • else <public-ip>.sslip.io — sslip.io is wildcard DNS that resolves
#     "<ip>.sslip.io" straight to <ip>, so Let's Encrypt's HTTP-01 challenge
#     works with ZERO DNS configuration. Caveat: every sslip.io host shares ONE
#     LE registered-domain rate limit, so for anything long-lived a real domain
#     is sturdier. sslip.io is the zero-config default.
step "Deriving the public hostname"
PUBLIC_IP=""
fetch_public_ip() {
  # DO metadata service first (link-local, only reachable from the droplet).
  PUBLIC_IP="$(curl -fsS --max-time 5 \
    http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || true)"
  # Fallbacks: public echo services (in case metadata is off or this isn't DO).
  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  fi
  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="$(curl -fsS --max-time 5 https://icanhazip.com 2>/dev/null || true)"
  fi
  # Strip any stray whitespace/newline.
  PUBLIC_IP="$(printf '%s' "$PUBLIC_IP" | tr -d '[:space:]')"
}

HOSTNAME_PUBLIC="${PARACHUTE_DOMAIN:-}"
if [ -n "$HOSTNAME_PUBLIC" ]; then
  ok "Using your domain: ${BOLD}${HOSTNAME_PUBLIC}${RESET}"
  info "Make sure an A-record for ${HOSTNAME_PUBLIC} points at this droplet's IP,"
  info "or Caddy's Let's Encrypt challenge will fail. (You can re-run this script"
  info "once DNS has propagated — it's idempotent.)"
else
  fetch_public_ip
  # A minimal IPv4 shape check — guards against a metadata blip returning junk.
  if printf '%s' "$PUBLIC_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    HOSTNAME_PUBLIC="${PUBLIC_IP}.sslip.io"
    ok "No PARACHUTE_DOMAIN set — using ${BOLD}${HOSTNAME_PUBLIC}${RESET} (sslip.io wildcard DNS)"
    info "sslip.io resolves <ip>.sslip.io → ${PUBLIC_IP}, so Let's Encrypt works with no DNS setup."
    info "Heads up: sslip.io shares one LE rate limit across all users — a BYO domain"
    info "(PARACHUTE_DOMAIN) is sturdier for anything long-lived."
  else
    warn "Couldn't determine this box's public IP (metadata + echo services all failed)."
    warn "Falling back to a LOOPBACK-ONLY install — no public HTTPS this run."
    warn "Set PARACHUTE_DOMAIN (or re-run once networking is up) to enable Caddy + public TLS."
    HOSTNAME_PUBLIC=""
  fi
fi

HUB_ORIGIN=""
[ -n "$HOSTNAME_PUBLIC" ] && HUB_ORIGIN="https://${HOSTNAME_PUBLIC}"

# ── 5. init (persist canonical origin BEFORE modules start) ──────────────────
# `parachute init` is the fresh-install front door. It installs + starts the hub
# as a systemd unit (reboot-survivable), installs the vault, and prints the URL.
#
# We pass:
#   --hub-origin https://<hostname>  — persists the canonical PUBLIC origin to
#                       the hub DB BEFORE the hub + modules spawn, so vault (and
#                       later scribe) come up with that origin in their accepted
#                       set in ONE pass. This is the Caddy-direct shape: the hub
#                       binds loopback, Caddy terminates public TLS in front. We
#                       only pass it when we resolved a public hostname.
#   --no-expose-prompt  — no tunnel; Caddy is the terminator (next step).
#   --no-browser        — there's no desktop browser on a droplet to open.
#
# init is idempotent: a re-run on an already-set-up box just confirms + reprints.
SUMMARY_FILE="${PARACHUTE_SETUP_SUMMARY:-/root/parachute-setup.txt}"
# Fall back to $HOME if /root isn't writable (e.g. non-root sudo install).
if ! ( : > "$SUMMARY_FILE" ) 2>/dev/null; then
  SUMMARY_FILE="$HOME/parachute-setup.txt"
  : > "$SUMMARY_FILE" 2>/dev/null || SUMMARY_FILE="/dev/null"
fi

step "Running parachute init (hub + vault, systemd unit)"
{
  echo "===== parachute init output ($(date -u '+%Y-%m-%d %H:%M:%S UTC')) ====="
  echo
} >> "$SUMMARY_FILE" 2>/dev/null || true

# Build init's args. --hub-origin only when we have a public origin.
INIT_ARGS=(--no-expose-prompt --no-browser)
if [ -n "$HUB_ORIGIN" ]; then
  INIT_ARGS+=(--hub-origin "$HUB_ORIGIN")
  info "Persisting canonical origin ${BOLD}${HUB_ORIGIN}${RESET} before modules start."
fi

# Capture init's output AND stream it live to stdout. If init fails, say so
# explicitly — under cloud-init the operator only has the log + this summary
# file to go on, so a bare `set -e` abort would be opaque.
parachute init "${INIT_ARGS[@]}" 2>&1 | tee -a "$SUMMARY_FILE" || {
  warn "parachute init failed. Full output is above and in:"
  warn "  $SUMMARY_FILE  (and /var/log/cloud-init-output.log on an unattended boot)"
  warn "Fix the issue and re-run this script — it's idempotent."
  exit 1
}

HUB_PORT="${PARACHUTE_HUB_PORT:-1939}"

# ── 5b. Ensure modules are actually running under the supervisor ──────────────
# Two fresh-box realities of `parachute init` this works around (both are hub
# bugs tracked upstream; this is the operator-facing belt-and-suspenders so the
# box is usable after ONE unattended boot — fully non-fatal):
#   1. init installs the vault module at @latest regardless of the channel we
#      installed above — so on `rc` it DOWNGRADES vault below the hub. Re-assert
#      the chosen channel so vault matches the hub.
#   2. init can start the hub supervisor BEFORE the vault entry is seeded into
#      services.json (a timing race lost on slow boxes) — leaving vault
#      registered but never spawned (502 at /vault/*). A restart makes the
#      supervisor re-scan and spawn it.
if [ "${CHANNEL}" != "latest" ]; then
  info "Re-asserting vault @ ${CHANNEL} (init installs modules at @latest)…"
  bun add -g "@openparachute/vault@${CHANNEL}" >/dev/null 2>&1 \
    || warn "Could not re-assert vault@${CHANNEL}; continuing with the installed version."
fi
step "Starting all modules under the supervisor"
parachute restart >/dev/null 2>&1 \
  || warn "parachute restart returned non-zero — check 'parachute status' after login."
# Verify vault answers through the hub proxy (give the child a moment to bind).
# 200 = open health; 401/403 = reachable but auth-gated (vault IS up); 502/000 = down.
vault_up=""
for _ in 1 2 3 4 5 6; do
  vcode="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    "http://127.0.0.1:${HUB_PORT}/vault/default/health" 2>/dev/null || echo 000)"
  case "$vcode" in
    200 | 401 | 403) vault_up="yes"; break ;;
  esac
  sleep 3
done
if [ -n "$vault_up" ]; then
  ok "Vault is running under the supervisor."
else
  warn "Vault isn't answering yet — after login, run 'parachute restart' or check 'parachute status'."
fi

# ── 6. read the one-time bootstrap token (no creds in config) ────────────────
# A fresh box with no admin and no PARACHUTE_INITIAL_ADMIN_* makes `parachute
# serve` enter "needs-setup" mode and mint an in-memory bootstrap token
# (`parachute-bootstrap-<rand>`), regenerated on EVERY hub restart and never
# persisted. The operator visits /admin/setup, pastes this token, and chooses
# their OWN username + password there — so no password ever lands in User Data,
# the droplet console, or DO metadata.
#
# We read it from the LOOPBACK hub (hub#576 hands the token to loopback callers
# only — a public request through Caddy is NOT loopback and won't get it). This
# runs AFTER the final `parachute restart` above, because each restart mints a
# fresh token; reading earlier would print a stale one. Pure-bash parse (no jq).
# Entirely non-fatal — if the read fails (or an admin already exists on a
# re-run), the summary still tells the operator how to finish.
BOOTSTRAP_TOKEN=""

step "Reading the one-time bootstrap token (set your password in the browser)"
SETUP_JSON="$(curl -fsS -H 'Accept: application/json' \
  "http://127.0.0.1:${HUB_PORT}/admin/setup" 2>/dev/null || true)"
BOOTSTRAP_TOKEN="$(printf '%s' "$SETUP_JSON" \
  | grep -oE 'parachute-bootstrap-[A-Za-z0-9_-]+' | head -1 || true)"

if [ -n "$BOOTSTRAP_TOKEN" ]; then
  ok "Bootstrap token ready — finish setup in your browser at /admin/setup."
else
  # No token: either an admin already exists (a re-run / already set up), or the
  # loopback read didn't return one. Either way, non-fatal — the summary tells
  # the operator how to sign in or re-read the token.
  info "No bootstrap token returned — this box may already have an admin (a re-run)."
  info "If so, just sign in at /login. The summary explains how to re-read it if needed."
fi

# ── 7. Caddy — public TLS terminator + reverse proxy ─────────────────────────
# Caddy fronts the loopback hub: it auto-provisions a Let's Encrypt cert for
# <hostname> and reverse-proxies HTTPS → 127.0.0.1:<hub-port>. Caddy sets
# X-Forwarded-Proto=https, which the hub honors → Secure cookies work end to end.
# Needs ports 80 + 443 reachable (DO droplets are open by default).
#
# This whole step is SKIPPED if we couldn't derive a public hostname (loopback
# fallback) — there's nothing to cert.
install_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    ok "Caddy already installed ($(caddy version 2>/dev/null | head -n1))"
    return 0
  fi
  info "Adding the official Caddy apt repo and installing…"
  # Official stable repo per caddyserver.com/docs/install (Debian/Ubuntu).
  apt_get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | $SUDO gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt_get update -qq
  apt_get install -y -qq caddy
  ok "Caddy installed"
}

write_caddyfile() {
  # Reverse-proxy <hostname> → the loopback hub. Caddy handles ACME/TLS itself.
  #
  # Caddy is the trusted edge now (it terminates public TLS in front of the
  # loopback hub), so harden the proxy headers as defense-in-depth:
  #   • Caddy already OVERWRITES X-Forwarded-For / -Proto / -Host with the real
  #     connection values by default — we keep that (it's what lets the hub know
  #     the request arrived over HTTPS, so Secure cookies work end to end).
  #   • We additionally STRIP the Cloudflare + Tailscale headers below. The hub's
  #     `layerOf` reads those as TRUST SIGNALS to decide how privileged a request
  #     is — but only a REAL Cloudflare / Tailscale edge may legitimately set
  #     them. A public client could otherwise forge e.g. `Cf-Connecting-Ip` to
  #     impersonate a more-trusted layer through our Caddy. Since this box fronts
  #     the hub with Caddy (not CF/Tailscale), these never have a legitimate
  #     inbound value here, so we drop any client-supplied copy.
  local caddyfile="/etc/caddy/Caddyfile"
  $SUDO mkdir -p /etc/caddy
  $SUDO tee "$caddyfile" >/dev/null <<CADDY
# Managed by Parachute install (install/digitalocean.sh). Re-run to refresh.
${HOSTNAME_PUBLIC} {
    reverse_proxy 127.0.0.1:${HUB_PORT} {
        # Strip client-supplied layer-spoofing trust signals — only a real
        # Cloudflare / Tailscale edge may set these; this Caddy is the edge.
        header_up -Cf-Ray
        header_up -Cf-Connecting-Ip
        header_up -Tailscale-Funnel-Request
        header_up -Tailscale-User-Login
    }
}
CADDY
  ok "Wrote ${caddyfile} → reverse_proxy 127.0.0.1:${HUB_PORT} (trust-signal headers stripped)"
}

if [ -n "$HOSTNAME_PUBLIC" ]; then
  step "Installing + configuring Caddy (public HTTPS)"
  # Guarded: a Caddy apt-repo/network failure must NOT abort the script under
  # `set -e` (hub + admin are already up by now). Degrade to loopback-only +
  # tell the operator how to finish, rather than leaving a half-install with no
  # summary. Clearing HOSTNAME_PUBLIC routes the summary to the loopback path.
  if ! install_caddy; then
    warn "Caddy install failed — hub is running but public HTTPS is NOT configured."
    warn "Re-run this script once the Caddy apt repo is reachable, or install Caddy by hand."
    HOSTNAME_PUBLIC=""
  elif ! write_caddyfile; then
    warn "Could not write /etc/caddy/Caddyfile — check permissions on /etc/caddy/."
    HOSTNAME_PUBLIC=""
  fi
fi
if [ -n "$HOSTNAME_PUBLIC" ]; then
  # Enable + start (or reload if already running). Caddy ships a systemd unit.
  $SUDO systemctl enable caddy >/dev/null 2>&1 || true
  if $SUDO systemctl is-active --quiet caddy 2>/dev/null; then
    $SUDO systemctl reload caddy 2>/dev/null || $SUDO systemctl restart caddy || \
      warn "Caddy reload/restart reported an error — check: systemctl status caddy"
    ok "Caddy reloaded with the new site config"
  else
    $SUDO systemctl start caddy 2>/dev/null || \
      warn "Caddy failed to start — check: systemctl status caddy ; journalctl -u caddy"
    ok "Caddy started"
  fi
  info "Caddy will fetch a Let's Encrypt cert for ${HOSTNAME_PUBLIC} on the first HTTPS hit."
  info "(Ports 80 + 443 must be reachable. DO droplets are open by default;"
  info " if you enabled ufw, run: ${SUDO} ufw allow 80,443/tcp)"
else
  step "Skipping Caddy (no public hostname)"
  warn "No public hostname resolved — the hub is loopback-only on this run."
  warn "Set PARACHUTE_DOMAIN (or fix networking) and re-run to enable public HTTPS."
fi

# ── 8. transcription by RAM (non-fatal) ──────────────────────────────────────
# Decide local vs cloud vs none from PARACHUTE_TRANSCRIBE + box RAM. EVERYTHING
# here is wrapped so a failure NEVER aborts the curl|bash under `set -euo
# pipefail` — transcription is a nice-to-have, not a setup gate.
#
# ORDERING INVARIANT: the bootstrap token was read in step 6, after the LAST hub
# restart (step 5b). `parachute install scribe` below spawns scribe as a
# supervised child and does NOT restart the hub (which would mint a fresh token
# and stale the one we wrote to the summary). Keep it that way — if a future
# `install` starts restarting the hub, move the token read to AFTER this step.
TRANSCRIBE_NOTE=""
MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
# Guard against awk succeeding with empty output (no MemTotal line) — an empty
# MEM_KB would make the arithmetic below fail under `set -e`.
[ -n "$MEM_KB" ] || MEM_KB=0
MEM_MB=$(( MEM_KB / 1024 ))
# Human-readable RAM for messages: show MB under 1 GB (so a ~1 GB box doesn't
# print a misleading "0 GB" from integer division), one-decimal GB at/above 1 GB.
if [ "$MEM_MB" -ge 1024 ]; then
  MEM_HUMAN="$(awk -v kb="$MEM_KB" 'BEGIN{printf "%.1f GB", kb/1024/1024}')"
else
  MEM_HUMAN="${MEM_MB} MB"
fi
# ~2 GB floor for local ASR; use KB so we don't round a 2 GB box down to 1.
TRANSCRIBE_MIN_KB=$(( 2 * 1024 * 1024 ))

TRANSCRIBE_CHOICE="${PARACHUTE_TRANSCRIBE:-auto}"
if [ "$TRANSCRIBE_CHOICE" = "auto" ]; then
  if [ "$MEM_KB" -ge "$TRANSCRIBE_MIN_KB" ]; then
    TRANSCRIBE_CHOICE="local"
  else
    TRANSCRIBE_CHOICE="none"
  fi
fi

# install_local_scribe runs entirely inside `|| { warn; }` guards — no step in
# here may propagate a non-zero exit to the parent shell.
install_local_scribe() {
  # Each command is guarded; a failure warns + returns 0 so the script proceeds.
  bun add -g "@openparachute/scribe@${CHANNEL:-latest}" || { warn "bun add @openparachute/scribe failed — skipping local ASR."; return 0; }
  parachute install scribe || { warn "parachute install scribe failed — skipping local ASR."; return 0; }
  if command -v parachute-scribe >/dev/null 2>&1; then
    parachute-scribe install-backend || { warn "parachute-scribe install-backend failed — engine not installed (cloud still works)."; return 0; }
  else
    warn "parachute-scribe binary not on PATH after install — engine not installed."
    return 0
  fi
  ok "Local transcription (Scribe) installed."
  return 0
}

step "Transcription (${MEM_HUMAN} RAM detected → ${TRANSCRIBE_CHOICE})"
case "$TRANSCRIBE_CHOICE" in
  local)
    if [ "$MEM_KB" -lt "$TRANSCRIBE_MIN_KB" ]; then
      warn "Local transcription wants ~2 GB RAM; this box has ${MEM_HUMAN}."
      warn "Installing anyway because PARACHUTE_TRANSCRIBE=local was set — it may be tight."
    fi
    info "Installing the local Scribe engine (this can take a minute; non-fatal if it fails)…"
    # The whole block is non-fatal: guard the call itself too.
    install_local_scribe || warn "Local transcription setup hit an error — continuing without it."
    TRANSCRIBE_NOTE="Local transcription: attempted on-box (see log above). Manage it from the admin UI."
    ;;
  cloud)
    info "Cloud transcription selected — add a provider key (e.g. Groq, ~\$0.04/hr) in the admin UI."
    TRANSCRIBE_NOTE="Transcription: install Scribe + add a cloud provider key (Groq) in the admin UI under Modules."
    ;;
  none|*)
    if [ "$MEM_KB" -lt "$TRANSCRIBE_MIN_KB" ] && [ "${PARACHUTE_TRANSCRIBE:-auto}" = "auto" ]; then
      info "Skipping local transcription — ${MEM_HUMAN} RAM is below the ~2 GB floor."
      info "Use a cloud provider (Groq, ~\$0.04/hr) instead, or pick a 2 GB droplet."
      TRANSCRIBE_NOTE="Transcription: skipped (RAM < 2 GB). Add a cloud provider (Groq) in the admin UI, or resize to 2 GB for on-box ASR."
    else
      info "Transcription skipped (PARACHUTE_TRANSCRIBE=none)."
      TRANSCRIBE_NOTE="Transcription: skipped. Add it later from the admin UI (local needs ~2 GB; cloud uses a provider key)."
    fi
    ;;
esac

# ── 9. summary + done ────────────────────────────────────────────────────────
PUBLIC_URL=""
[ -n "$HOSTNAME_PUBLIC" ] && PUBLIC_URL="https://${HOSTNAME_PUBLIC}"
# Where the operator finishes setup in the browser. Public if we have a hostname,
# else the loopback admin URL (read it from the DO console on the box).
SETUP_URL="${PUBLIC_URL:+${PUBLIC_URL}/admin/setup}"
[ -n "$SETUP_URL" ] || SETUP_URL="http://127.0.0.1:${HUB_PORT}/admin/setup"
LOGIN_URL="${PUBLIC_URL:+${PUBLIC_URL}/login}"
[ -n "$LOGIN_URL" ] || LOGIN_URL="http://127.0.0.1:${HUB_PORT}/login"

# Build the login / next-steps block once (plain text, no color — the summary
# file should stay copy-pasteable), then emit it to the file and to stdout.
if [ -n "$PUBLIC_URL" ]; then
  URL_LINE="Public URL:  ${PUBLIC_URL}"
else
  URL_LINE="Public URL:  (none — loopback only; set PARACHUTE_DOMAIN and re-run)
Local URL:   http://127.0.0.1:${HUB_PORT}/admin/setup"
fi

# The one-time bootstrap-token flow: the operator sets their OWN password in the
# browser. No credential was ever put in User Data, the console, or metadata.
if [ -n "$BOOTSTRAP_TOKEN" ]; then
  read -r -d '' LOGIN_BLOCK <<EOF || true
Finish setup IN YOUR BROWSER — set your own username + password (nothing was
stored in your cloud config). Use the one-time bootstrap token below.
------------------------------------------------------------
  >>> BOOTSTRAP TOKEN:  ${BOOTSTRAP_TOKEN}
  >>> SETUP URL:        ${SETUP_URL}
------------------------------------------------------------
  1. Open  ${SETUP_URL}  in your browser.
     (First load may take a few seconds while Caddy fetches the TLS cert.)
  2. Paste the BOOTSTRAP TOKEN above, then choose your username + password.
  3. That's it — you're the owner, and your password never touched the cloud.

  The token is single-use and regenerates if the hub restarts. To re-read the
  current one from the DO droplet Console (no SSH key needed), run on the box:
      curl -fsS -H 'Accept: application/json' http://127.0.0.1:${HUB_PORT}/admin/setup \\
        | grep -oE 'parachute-bootstrap-[A-Za-z0-9_-]+' | head -1
EOF
else
  read -r -d '' LOGIN_BLOCK <<EOF || true
Already set up — this box appears to have an owner account already.
------------------------------------------------------------
  Sign in at  ${LOGIN_URL}

  If you actually still need to create the first owner, the hub mints a one-time
  bootstrap token when no admin exists. Read the current one from the box
  (DO droplet Console — no SSH key needed):
      curl -fsS -H 'Accept: application/json' http://127.0.0.1:${HUB_PORT}/admin/setup \\
        | grep -oE 'parachute-bootstrap-[A-Za-z0-9_-]+' | head -1
  then open  ${SETUP_URL}  and paste it.
EOF
fi

read -r -d '' NEXT_STEPS <<EOF || true

================================================================================
Parachute is installed — hub + vault running as a systemd unit${HOSTNAME_PUBLIC:+, behind Caddy (public HTTPS)}.
================================================================================

${URL_LINE}

${LOGIN_BLOCK}

${TRANSCRIBE_NOTE}

Connect your AI — point any MCP client at:
    ${PUBLIC_URL:-<your-hub-origin>}/vault/default/mcp
The admin SPA's Connect toggle hands you a copy-paste 'claude mcp add' command.
If the Claude connector fails right after consent, it's almost never the hub —
see the Cloudflare/edge note at https://parachute.computer/deploy/digitalocean/

Everything lives under ~/.parachute/ on this box. You own all of it.
================================================================================
EOF

# Append to the summary file (for the operator to read later over SSH/console)…
printf '%s\n' "$NEXT_STEPS" >> "$SUMMARY_FILE" 2>/dev/null || true
# …and print it to stdout (for the interactive operator watching live).
step "Done"
if [ -n "$PUBLIC_URL" ]; then
  ok "Public URL:  ${BOLD}${PUBLIC_URL}${RESET}"
else
  ok "Local admin URL:  ${BOLD}http://127.0.0.1:${HUB_PORT}/admin/setup${RESET}"
fi
# Surface the bootstrap token + setup URL prominently up top, before the long
# NEXT_STEPS block — it's the one thing the operator needs to finish setup.
if [ -n "$BOOTSTRAP_TOKEN" ]; then
  ok "Setup URL:   ${BOLD}${SETUP_URL}${RESET}"
  ok "Bootstrap token (paste it there): ${BOLD}${BOOTSTRAP_TOKEN}${RESET}"
fi
printf '%s\n' "$NEXT_STEPS"
if [ "$SUMMARY_FILE" != "/dev/null" ]; then
  info "Saved this summary to ${BOLD}${SUMMARY_FILE}${RESET}."
fi
