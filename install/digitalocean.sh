#!/usr/bin/env bash
#
# Parachute — DigitalOcean (and any fresh Ubuntu box) one-command setup.
#
#   curl -fsSL https://parachute.computer/install/digitalocean.sh | bash
#
# What it does, on a fresh Ubuntu 24.04 droplet (run as root, or a sudo user):
#   1. Installs Bun (the JS runtime Parachute is built on), if not already present.
#   2. Installs @openparachute/hub + @openparachute/vault globally via Bun.
#   3. Runs `parachute init` — installs + starts the hub as a systemd unit
#      (survives reboots), installs the vault, and prints your local connect URL.
#   4. Tells you the next step: exposing your hub to the internet (your call —
#      this is the durable, own-your-data path, NOT zero-config).
#
# Idempotent — safe to re-run. Each step skips itself if already done.
#
# ─────────────────────────────────────────────────────────────────────────────
# Droplet sizing
#   $6/mo  (1 GB / 1 vCPU)  — comfortable for hub + vault. The RAM headroom
#                             matters: Bun + the vault index want room to breathe.
#   $12/mo (2 GB / 1 vCPU)  — pick this if you'll also run Claude Code on the box,
#                             or add the scribe (transcription) module.
#   Image: Ubuntu 24.04 LTS x64.
# ─────────────────────────────────────────────────────────────────────────────
#
# This script touches only your own box. It installs nothing Parachute-operated
# between you and your data — everything lands under ~/.parachute/ on your disk.

set -euo pipefail

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

printf "\n%sParachute — DigitalOcean / Ubuntu setup%s\n" "$BOLD" "$RESET"
printf "%shub + vault on your own box, in one command%s\n" "$DIM" "$RESET"

# ── 1. base packages (curl, unzip — Bun's installer needs unzip) ─────────────
step "Checking base packages (curl, unzip)"
NEED_PKGS=""
command -v curl  >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS curl"
command -v unzip >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS unzip"
if [ -n "$NEED_PKGS" ]; then
  info "Installing:$NEED_PKGS"
  # apt-get is the Ubuntu package manager. -y answers prompts automatically.
  # DEBIAN_FRONTEND=noninteractive keeps apt from blocking on tzdata-style dialogs.
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # shellcheck disable=SC2086  # intentional word-split: pass each package as its own arg
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $NEED_PKGS
  ok "Base packages installed"
else
  ok "curl + unzip already present"
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
# `bun add -g` installs the global packages. `parachute init` (run by the hub
# package) ALSO installs the vault — we add the vault explicitly too so a
# `bun link`-free, offline-ish re-run still has it. All three are idempotent.
step "Installing Parachute (hub + vault)"
bun add -g @openparachute/hub @openparachute/vault
ok "@openparachute/hub + @openparachute/vault installed"

if ! command -v parachute >/dev/null 2>&1; then
  echo "The 'parachute' binary isn't on PATH after install. Open a fresh shell"
  echo "(so ~/.bun/bin is picked up) and re-run, or run: export PATH=\"\$HOME/.bun/bin:\$PATH\""
  exit 1
fi

# ── 4. init ──────────────────────────────────────────────────────────────────
# `parachute init` is the fresh-install front door. It installs + starts the hub
# as a systemd unit (reboot-survivable), installs the vault, and prints the
# admin/setup URL + a one-time bootstrap token.
#
# We pass:
#   --no-expose-prompt  — don't ask about public exposure here. Exposing your hub
#                         is a deliberate next step (see "Next" below) — bring your
#                         own Cloudflare account+domain or Tailscale. NOT zero-config.
#   --no-browser        — there's no desktop browser on a droplet to open.
#
# init is idempotent: a re-run on an already-set-up box just confirms + reprints
# the URL.
step "Running parachute init (hub + vault, systemd unit)"
parachute init --no-expose-prompt --no-browser

# ── 5. next steps ────────────────────────────────────────────────────────────
HUB_PORT="${PARACHUTE_HUB_PORT:-1939}"
step "Done — hub + vault are running on this box"
ok "Local admin URL:  ${BOLD}http://127.0.0.1:${HUB_PORT}/admin/setup${RESET}"
info "(init printed the canonical URL + a one-time bootstrap token just above.)"

cat <<EOF

${BOLD}Next: finish setup, then reach it from your phone & your AI${RESET}

  ${BOLD}1. Finish the wizard${RESET} — two ways:
       • Headless, right here:   ${DIM}parachute init --cli-wizard${RESET}
       • From your laptop browser over SSH:
           ${DIM}ssh -L ${HUB_PORT}:127.0.0.1:${HUB_PORT} root@<this-droplet-ip>${RESET}
         then open ${DIM}http://127.0.0.1:${HUB_PORT}/admin/setup${RESET} on your laptop
         and paste the bootstrap token init printed above.

  ${BOLD}2. Expose it (the durable, own-your-data path)${RESET}
     Public exposure is ${BOLD}not${RESET} zero-config — it uses ${BOLD}your own${RESET} account, so the
     URL and the data stay yours. Pick one:

       • ${BOLD}Cloudflare Tunnel${RESET} (clean public HTTPS — what claude.ai's
         connector needs). Needs a domain on a Cloudflare zone (free tier is fine):
           ${DIM}parachute expose public --cloudflare --domain vault.example.com${RESET}

       • ${BOLD}Tailscale Funnel${RESET} (no domain needed; a *.ts.net URL on your tailnet).
         Set up Tailscale on the box, then:
           ${DIM}parachute expose public${RESET}

     Full walkthrough (both paths, plus the Cloudflare bot-protection gotcha
     that breaks the Claude connector):
       ${BLUE}https://parachute.computer/deploy/digitalocean/${RESET}

  ${BOLD}3. Connect your AI${RESET} — point any MCP client at:
       ${DIM}<your-hub-origin>/vault/<vault-name>/mcp${RESET}
     The done screen / admin SPA hands you a copy-paste \`claude mcp add\` command.

${DIM}Everything lives under ~/.parachute/ on this box. You own all of it.${RESET}
EOF
