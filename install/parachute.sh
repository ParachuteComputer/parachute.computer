#!/usr/bin/env bash
# Parachute — one setup script, Mac and Linux.
#
#   curl -fsSL https://parachute.computer/install/parachute.sh | bash
#
# Replaces two divergent paths: an Ubuntu-only `server.sh` that installed the
# retired scribe and never installed the app, and a Mac path that was a manual
# `bun add -g` requiring you to have already installed Bun yourself. Same
# command on both now, and both end at the same place: a hub, a vault, the app
# as the front door, and local transcription that has been proven to work.
#
# What it does, in order:
#   1. Prerequisites for this platform (bun, ffmpeg, and on Linux the base
#      packages a fresh cloud image lacks).
#   2. Installs @openparachute/hub + @openparachute/vault.
#   3. `parachute init` — starts the hub under launchd/systemd, installs the
#      vault and the app, opens the setup wizard.
#   4. Local transcription (whisper.cpp + a model), verified end-to-end.
#   5. On a Linux box with PARACHUTE_DOMAIN set: Caddy + a real certificate.
#
# Options (flags or env — flags win):
#   --domain <host>        PARACHUTE_DOMAIN      public hostname; enables Caddy (Linux)
#   --channel <latest|rc>  PARACHUTE_CHANNEL     npm dist-tag to install (default latest)
#   --no-transcription     PARACHUTE_NO_TRANSCRIPTION=1
#   --dry-run              PARACHUTE_DRY_RUN=1   print every step, change nothing
#   --help
#
# NEVER prompts. `curl | bash` means stdin is the pipe, not your terminal, so a
# prompt would either hang forever or silently read a line of the script itself.
# Everything is a flag or an environment variable.

set -euo pipefail

# ── output ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'; BLUE=$'\033[34m'
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
else
  BOLD=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""; RED=""
fi
step() { printf "\n%s==>%s %s%s%s\n" "$BLUE" "$RESET" "$BOLD" "$1" "$RESET"; }
info() { printf "    %s\n" "$1"; }
ok()   { printf "    %s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "    %s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
die()  { printf "\n%serror:%s %s\n" "$RED" "$RESET" "$1" >&2; exit 1; }

# ── options ──────────────────────────────────────────────────────────────────
DOMAIN="${PARACHUTE_DOMAIN:-}"
CHANNEL="${PARACHUTE_CHANNEL:-latest}"
NO_TRANSCRIPTION="${PARACHUTE_NO_TRANSCRIPTION:-}"
DRY_RUN="${PARACHUTE_DRY_RUN:-}"

usage() {
  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --domain)  DOMAIN="${2:-}"; [ -n "$DOMAIN" ] || die "--domain needs a hostname"; shift 2 ;;
    --channel) CHANNEL="${2:-}"; [ -n "$CHANNEL" ] || die "--channel needs latest or rc"; shift 2 ;;
    --no-transcription) NO_TRANSCRIPTION=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage ;;
    *) die "unknown option: $1  (try --help)" ;;
  esac
done

case "$CHANNEL" in
  latest|rc) ;;
  *) die "--channel must be 'latest' or 'rc' (got '$CHANNEL')" ;;
esac

# Every mutating command goes through `run`, which is what makes --dry-run
# trustworthy: there is no second path that could quietly do something.
run() {
  if [ -n "$DRY_RUN" ]; then
    printf "    %s[dry-run]%s %s\n" "$YELLOW" "$RESET" "$*"
    return 0
  fi
  "$@"
}

# ── platform ─────────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Darwin) PLATFORM="mac" ;;
  Linux)  PLATFORM="linux" ;;
  *) die "unsupported platform: $OS. Parachute self-hosts on macOS and Linux." ;;
esac

# Only Linux needs sudo — a Mac install is entirely in the user's home.
SUDO=""
if [ "$PLATFORM" = "linux" ] && [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "not root and no sudo — re-run as root."
  SUDO="sudo"
fi

step "Parachute setup — ${PLATFORM} (${ARCH}), channel ${CHANNEL}"
[ -n "$DRY_RUN" ] && warn "DRY RUN — nothing will be installed or changed."
[ -n "$DOMAIN" ] && info "Public hostname: ${DOMAIN}"

# ── 1. prerequisites ─────────────────────────────────────────────────────────
# apt wrapper that survives cloud-init's early boot: on first boot, cloud-init's
# own apt run (and unattended-upgrades) hold the dpkg locks for a minute or two.
# `DPkg::Lock::Timeout=120` WAITS for the lock instead of failing instantly with
# "Could not get lock" — the single most common unattended-install failure.
apt_get() {
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 "$@"
}

install_pkgs_linux() {
  [ $# -gt 0 ] || return 0
  if command -v apt-get >/dev/null 2>&1; then
    apt_get update -qq
    apt_get install -y -qq "$@"
  elif command -v dnf >/dev/null 2>&1; then
    run $SUDO dnf install -y -q "$@"
  elif command -v pacman >/dev/null 2>&1; then
    run $SUDO pacman -Sy --noconfirm "$@"
  else
    warn "No apt/dnf/pacman found — install these yourself: $*"
    return 1
  fi
}

step "Checking prerequisites"
if [ "$PLATFORM" = "linux" ]; then
  NEED=""
  command -v curl  >/dev/null 2>&1 || NEED="$NEED curl"
  command -v unzip >/dev/null 2>&1 || NEED="$NEED unzip"
  [ -f /etc/ssl/certs/ca-certificates.crt ] || NEED="$NEED ca-certificates"
  if [ -n "$NEED" ]; then
    info "Installing base packages:$NEED"
    # shellcheck disable=SC2086  # intentional word-split: one arg per package
    install_pkgs_linux $NEED || die "couldn't install base packages"
  fi
  ok "Base packages present"
fi

# Bun. On Mac this was the documented manual prerequisite ("You'll need Bun 1.3
# or later") and the single most common reason a Mac install stalled before it
# began. Installing it is one line; making someone go read another site first is
# the friction this script exists to delete.
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
if command -v bun >/dev/null 2>&1; then
  ok "bun $(bun --version) already installed"
elif [ -x "$BUN_INSTALL/bin/bun" ]; then
  export PATH="$BUN_INSTALL/bin:$PATH"
  ok "bun $(bun --version) found in $BUN_INSTALL"
else
  info "Installing bun…"
  run bash -c 'curl -fsSL https://bun.sh/install | bash'
  export PATH="$BUN_INSTALL/bin:$PATH"
  if [ -z "$DRY_RUN" ]; then
    command -v bun >/dev/null 2>&1 || die "bun install finished but bun isn't on PATH ($BUN_INSTALL/bin)"
    ok "bun $(bun --version) installed"
  fi
fi

# ffmpeg — required for transcription regardless of provider, because voice
# recordings arrive as webm/opus and every local engine wants 16 kHz mono WAV.
# Checked here rather than inside `transcription install` so a missing system
# package surfaces before a 400 MB model download, not after.
if [ -n "$NO_TRANSCRIPTION" ]; then
  info "Skipping ffmpeg (transcription disabled)"
elif command -v ffmpeg >/dev/null 2>&1; then
  ok "ffmpeg present"
elif [ "$PLATFORM" = "mac" ]; then
  if command -v brew >/dev/null 2>&1; then
    info "Installing ffmpeg via Homebrew…"
    run brew install ffmpeg || warn "ffmpeg install failed — transcription will be off until you install it"
  else
    warn "No Homebrew — install ffmpeg yourself for transcription (https://brew.sh, then: brew install ffmpeg)"
  fi
else
  info "Installing ffmpeg…"
  install_pkgs_linux ffmpeg || warn "ffmpeg install failed — transcription will be off until you install it"
fi

# ── 2. parachute ─────────────────────────────────────────────────────────────
step "Installing Parachute (hub + vault, channel: ${CHANNEL})"
run bun add -g "@openparachute/hub@${CHANNEL}" "@openparachute/vault@${CHANNEL}"
ok "hub + vault installed"

# Put bun + parachute on the system PATH NOW, so `parachute …` works in this
# very shell rather than only after a re-login. Idempotent and non-fatal.
if [ "$PLATFORM" = "linux" ]; then
  for b in bun parachute parachute-vault; do
    src="$BUN_INSTALL/bin/$b"
    [ -x "$src" ] || [ -n "$DRY_RUN" ] || continue
    run $SUDO ln -sf "$src" "/usr/local/bin/$b" 2>/dev/null \
      || warn "couldn't symlink $b into /usr/local/bin — parachute still works after 'source ~/.bashrc'"
  done
fi
export PATH="$BUN_INSTALL/bin:$PATH"

# ── 3. init: hub up, vault + app installed, wizard ready ─────────────────────
# `parachute init` is the one place that knows how to bring the hub up under
# this platform's process manager, install the vault and the app, and open the
# wizard. Reimplementing any of that here would be a second copy that drifts.
step "Starting the hub and installing your vault + app"
# --no-expose-prompt is NOT optional here. `parachute init` offers an
# interactive exposure question when it detects a terminal, and under
# `curl … | bash` stdin is the PIPE — the prompt would either hang or consume a
# line of this script as its answer. Exposure is this script's job anyway
# (--domain, below), so the question is redundant as well as dangerous.
#
# --no-browser on a server: there's no browser to open, and init would just
# print a failed `xdg-open`. Locally we let it open the wizard, which is the
# whole point of finishing here.
INIT_ARGS=(--no-expose-prompt --channel "$CHANNEL")
if [ "$PLATFORM" = "linux" ]; then
  # No browser to open on a server, and the public origin isn't resolved yet
  # (sslip.io needs the IP), so the HTTPS step below sets it with
  # `parachute hub set-origin` once the hostname is known.
  INIT_ARGS+=(--no-browser)
fi
run parachute init "${INIT_ARGS[@]}"
ok "hub running; vault + app installed"

# ── 4. transcription ─────────────────────────────────────────────────────────
# Turns voice memos into text locally. `transcription install` picks a model
# sized to this host's RAM, downloads it, and VERIFIES a real transcription
# before reporting success — so a green line here means it actually works.
if [ -n "$NO_TRANSCRIPTION" ]; then
  step "Skipping transcription (--no-transcription)"
  info "Set it up later with: parachute-vault transcription install"
else
  step "Setting up local transcription"
  info "Downloads a speech model (a few hundred MB) and verifies it end-to-end."
  if run parachute-vault transcription install --yes; then
    ok "Transcription ready"
  else
    # Never fatal: a working Parachute that can't transcribe is still a working
    # Parachute, and failing the whole install over an optional extra would be
    # a much worse outcome than a warning.
    warn "Transcription setup didn't complete — everything else is fine."
    warn "Retry any time: parachute-vault transcription install"
  fi
fi

# ── 5. public HTTPS (Linux) ──────────────────────────────────────────────────
# A Linux box gets HTTPS with or without a domain of your own. Without one we
# use sslip.io — wildcard DNS that resolves `<ip>.sslip.io` straight to <ip>, so
# Let's Encrypt's HTTP-01 challenge succeeds with ZERO DNS configuration. That
# zero-config path is what makes "paste one line into a fresh box" actually end
# at a working HTTPS URL, so it is not an optional nicety.
fetch_public_ip() {
  # Cloud metadata first (link-local, only reachable from inside the instance),
  # then public echo services in case metadata is disabled or this isn't a cloud
  # box at all. Every call is time-boxed: a hung metadata endpoint must not
  # wedge the install.
  PUBLIC_IP="$(curl -fsS --max-time 5 \
    http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || true)"
  [ -n "$PUBLIC_IP" ] || PUBLIC_IP="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  [ -n "$PUBLIC_IP" ] || PUBLIC_IP="$(curl -fsS --max-time 5 https://icanhazip.com 2>/dev/null || true)"
  PUBLIC_IP="$(printf '%s' "$PUBLIC_IP" | tr -d '[:space:]')"
}

PUBLIC_HOST="$DOMAIN"
if [ "$PLATFORM" = "linux" ] && [ -z "$PUBLIC_HOST" ]; then
  fetch_public_ip
  # Shape-check the IPv4 — guards against a metadata blip returning an error
  # page, which would otherwise become a nonsense hostname Caddy can't serve.
  if printf '%s' "${PUBLIC_IP:-}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    PUBLIC_HOST="${PUBLIC_IP}.sslip.io"
    info "No --domain given — using ${PUBLIC_HOST} (sslip.io wildcard DNS, no setup needed)"
    info "Heads up: sslip.io shares one Let's Encrypt rate limit across all users."
    info "A domain of your own is sturdier: re-run with --domain yours.example.com"
  else
    warn "Couldn't determine a public IP — staying on localhost."
    warn "Expose it later with: parachute expose tailnet"
  fi
elif [ -n "$DOMAIN" ] && [ "$PLATFORM" = "linux" ]; then
  info "Point an A-record for ${DOMAIN} at this box before/while this runs,"
  info "or Let's Encrypt's challenge fails. Re-run once DNS lands — it's idempotent."
fi

if [ -n "$PUBLIC_HOST" ] && [ "$PLATFORM" = "linux" ]; then
  DOMAIN="$PUBLIC_HOST"
  step "Serving ${DOMAIN} over HTTPS"
  if command -v caddy >/dev/null 2>&1; then
    ok "Caddy already installed"
  else
    info "Installing Caddy…"
    if command -v apt-get >/dev/null 2>&1; then
      run bash -c "curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | $SUDO gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
      run bash -c "curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | $SUDO tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null"
      apt_get update -qq
      apt_get install -y -qq caddy
    else
      install_pkgs_linux caddy || warn "install Caddy yourself, then re-run with --domain"
    fi
  fi
  if [ -z "$DRY_RUN" ]; then
    printf '%s {\n\treverse_proxy 127.0.0.1:1939\n}\n' "$DOMAIN" | $SUDO tee /etc/caddy/Caddyfile >/dev/null
  else
    info "[dry-run] write /etc/caddy/Caddyfile for ${DOMAIN} → 127.0.0.1:1939"
  fi
  run $SUDO systemctl reload caddy 2>/dev/null || run $SUDO systemctl restart caddy || warn "couldn't reload Caddy"
  # The hub's OAuth issuer must match the public origin, or every token it mints
  # is rejected at the door it was minted for.
  run parachute hub set-origin "https://${DOMAIN}" || warn "couldn't set the hub origin — run: parachute hub set-origin https://${DOMAIN}"
  ok "https://${DOMAIN} is live"
elif [ -n "$DOMAIN" ]; then
  warn "--domain is a Linux-server option; on a Mac use: parachute expose public --cloudflare --domain ${DOMAIN}"
fi

# ── done ─────────────────────────────────────────────────────────────────────
step "Done"
if [ -n "$DOMAIN" ] && [ "$PLATFORM" = "linux" ]; then
  info "Open  https://${DOMAIN}  to finish setup in your browser."
else
  info "Open  http://127.0.0.1:1939  to finish setup in your browser."
fi
cat <<'NEXT'

    What you have:
      hub          the coordinator, on :1939
      vault        your notes, tags, and attachments
      app          the front door — "/" lands here
      transcribe   voice memos become text, locally

    Useful next:
      parachute status                     what's installed and running
      parachute doctor                     check health, get the one fix
      parachute-vault transcription status is transcription working
      parachute expose tailnet             reach it from your phone

NEXT
