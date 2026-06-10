#!/usr/bin/env bash
#
# Fedora Workstation (44+) post-install setup.
# Idempotent: safe to run multiple times — each step skips work already done.
#
# Usage:
#   ./setup.sh            # interactive picker (runs all steps if non-interactive)
#   ./setup.sh --yes      # no prompts; run all steps
#   ./setup.sh --help
#
# The NVIDIA step auto-detects the GPU: it installs the driver only on NVIDIA
# hardware and skips itself otherwise.
#
set -Eeuo pipefail

# ---- colors (disabled when not writing to a terminal) ----------------------

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

# ---- output helpers --------------------------------------------------------

info()  { printf '%s==>%s %s\n'   "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s  ✓%s %s\n'   "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s  !%s %s\n'   "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf '%s  ✗%s %s\n'   "$C_RED"    "$C_RESET" "$*"; }
skip()  { printf '%s    skip: %s%s\n' "$C_DIM" "$*" "$C_RESET"; }

rule() {
  local w; w="$(tput cols 2>/dev/null || echo 60)"; [ "$w" -gt 72 ] && w=72
  printf '%s' "$C_DIM"; printf '─%.0s' $(seq 1 "$w"); printf '%s\n' "$C_RESET"
}

center() {  # text width — pad text to width, centered
  local text="$1" width="$2" len pad
  len=${#text}; pad=$(( (width - len) / 2 ))
  printf '%*s%s%*s' "$pad" '' "$text" "$(( width - len - pad ))" ''
}

banner() {
  local w=40 bar
  bar="$(printf '─%.0s' $(seq 1 "$w"))"
  printf '\n%s%s  ┌%s┐\n' "$C_BOLD" "$C_CYAN" "$bar"
  printf   '  │%s│\n'  "$(center 'Fedora Setup' "$w")"
  printf   '  │%s│\n'  "$(center 'post-install setup · Workstation 44+' "$w")"
  printf   '  └%s┘%s\n' "$bar" "$C_RESET"
}

step_header() {  # idx total label
  printf '\n%s%s[%s/%s]%s %s%s%s\n' \
    "$C_BOLD" "$C_BLUE" "$1" "$2" "$C_RESET" "$C_BOLD" "$3" "$C_RESET"
}

# Deferred action items, shown in the final summary.
NOTES=()
add_note() { NOTES+=("$1"); }

# A yes/no prompt. Returns success on y/Y. Non-interactive defaults to the arg ($2: 0/1).
ask() {
  local q="$1" default="${2:-0}" ans
  if [ "$INTERACTIVE" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then
    [ "$default" -eq 1 ]; return
  fi
  printf '%s %s[y/N]%s ' "$q" "$C_DIM" "$C_RESET"
  read -r ans || ans=''
  [[ "$ans" =~ ^[Yy] ]]
}

# ---- low-level helpers -----------------------------------------------------

ensure_line() {  # line file — append only if not already present
  local line="$1" file="$2"
  touch "$file"
  if grep -qxF -- "$line" "$file"; then
    skip "already in ${file/#$HOME/\~}: $line"
  else
    printf '%s\n' "$line" >> "$file"
    ok "added to ${file/#$HOME/\~}: $line"
  fi
}

pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }

ensure_rpmfusion() {
  local fed; fed="$(rpm -E %fedora)"
  if pkg_installed rpmfusion-free-release && pkg_installed rpmfusion-nonfree-release; then
    skip "RPM Fusion already enabled"
    return
  fi
  info "enabling RPM Fusion (free + nonfree)"
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fed}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fed}.noarch.rpm"
}

dnf_install() {
  local missing=()
  for p in "$@"; do
    if pkg_installed "$p"; then skip "$p already installed"; else missing+=("$p"); fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    info "installing: ${missing[*]}"
    sudo dnf install -y "${missing[@]}"
  fi
}

# ---- steps -----------------------------------------------------------------

step_system_update() {
  sudo dnf upgrade --refresh -y
  add_note "If the kernel was updated, reboot before NVIDIA or other kernel-module steps."
}

step_dnf_speedup() {
  local conf=/etc/dnf/dnf.conf
  for kv in "max_parallel_downloads=10" "defaultyes=True"; do
    local key="${kv%%=*}"
    if sudo grep -qE "^${key}=" "$conf"; then
      skip "$key already set in $conf"
    else
      echo "$kv" | sudo tee -a "$conf" >/dev/null
      ok "added to $conf: $kv"
    fi
  done
}

step_vscode() {
  if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
    info "importing Microsoft repo"
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
  else
    skip "vscode.repo already present"
  fi
  dnf_install code
}

step_chrome() {
  dnf_install fedora-workstation-repositories
  if pkg_installed google-chrome-stable; then
    skip "google-chrome-stable already installed"
  else
    # Enable the (disabled-by-default) repo just for this install; Chrome's RPM
    # then drops its own repo file for future updates. Avoids needing the
    # config-manager dnf plugin, which isn't always present on DNF 5.
    info "installing google-chrome-stable"
    sudo dnf install -y --enablerepo=google-chrome google-chrome-stable
  fi
}

step_gnome() {
  dnf_install gnome-tweaks gnome-extensions-app
  add_note "Browse/toggle GNOME extensions at https://extensions.gnome.org/ (install the browser connector first)."
}

step_zsh() {
  dnf_install zsh

  local zsh_path; zsh_path="$(command -v zsh)"
  if [ "${SHELL:-}" = "$zsh_path" ]; then
    skip "zsh is already the default shell"
  else
    info "setting zsh as default shell (you may be prompted for your password)"
    if chsh -s "$zsh_path"; then
      add_note "Log out and back in for zsh to become your default shell."
    else
      warn "chsh failed — set it manually with: chsh -s $zsh_path"
    fi
  fi

  local zshrc="$HOME/.zshrc"
  info "ensuring aliases in ~/.zshrc"
  ensure_line '# Aliases'                                  "$zshrc"
  ensure_line 'alias zshrc="code ~/.zshrc"'               "$zshrc"
  ensure_line 'alias reload="source ~/.zshrc"'            "$zshrc"
  ensure_line 'alias c="clear"'                           "$zshrc"
  ensure_line 'alias update="sudo dnf upgrade --refresh"' "$zshrc"
}

step_zsh_plugins() {
  clone_if_missing() {
    local url="$1" dir="$2"
    if [ -d "$dir" ]; then skip "${dir/#$HOME/\~} already cloned"; else
      info "cloning $url"
      git clone --depth 1 "$url" "$dir"
    fi
  }
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions      "$HOME/.zsh/zsh-autosuggestions"
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting  "$HOME/.zsh/zsh-syntax-highlighting"

  if command -v starship >/dev/null 2>&1; then
    skip "starship already installed"
  else
    info "installing starship"
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
  fi

  # Wire up ~/.zshrc — order matters: autosuggestions, then highlighting, then starship.
  local zshrc="$HOME/.zshrc"
  ensure_line '# Autosuggestions'                                                 "$zshrc"
  ensure_line 'source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh'         "$zshrc"
  ensure_line '# Syntax highlighting (must come after autosuggestions)'           "$zshrc"
  ensure_line 'source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' "$zshrc"
  ensure_line '# Starship prompt (always last)'                                   "$zshrc"
  ensure_line 'eval "$(starship init zsh)"'                                       "$zshrc"
  add_note "Restart your shell or run 'source ~/.zshrc' to load the plugins."
}

step_nvidia() {
  if ! lspci | grep -Ei 'vga|3d|display' | grep -qi nvidia; then
    skip "no NVIDIA GPU detected — skipping driver"
    return
  fi
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    skip "nvidia-smi works — proprietary driver already active"
    return
  fi

  warn "The driver must match your running kernel. Updating first..."
  sudo dnf upgrade --refresh -y

  ensure_rpmfusion
  dnf_install akmod-nvidia xorg-x11-drv-nvidia-cuda

  warn "akmod is building the kernel module in the background (~5 min)."
  add_note "NVIDIA: wait for the module to build ('modinfo -F version nvidia' prints a version), then reboot and check 'nvidia-smi'."
}

step_codecs() {
  # Fedora ships without patent-encumbered codecs — needed for video playback
  # and hardware decode. Lives in RPM Fusion.
  ensure_rpmfusion
  info "swapping in full ffmpeg"
  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || skip "ffmpeg already in place (nothing to swap)"
  info "installing multimedia group"
  sudo dnf group install -y multimedia

  # Hardware video decode, per GPU vendor.
  local gpus; gpus="$(lspci | grep -Ei 'vga|3d|display' || true)"
  if grep -qi nvidia <<<"$gpus"; then
    dnf_install libva-nvidia-driver   # NVIDIA: VA-API via NVDEC
  fi
  if grep -qiE 'amd|ati|radeon' <<<"$gpus"; then
    # Fedora's stock mesa drivers have H.264/H.265 stripped (patents);
    # the RPM Fusion "freeworld" builds re-enable them.
    info "swapping in mesa freeworld drivers (AMD hardware decode)"
    sudo dnf swap -y mesa-va-drivers    mesa-va-drivers-freeworld    || skip "mesa-va-drivers already freeworld"
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || skip "mesa-vdpau-drivers already freeworld"
  fi
}

step_steam() {
  ensure_rpmfusion
  dnf_install steam
}

step_firmware() {
  dnf_install fwupd
  info "refreshing firmware metadata from LVFS"
  sudo fwupdmgr refresh --force || true
  info "applying firmware updates (if any)"
  sudo fwupdmgr update -y || skip "no firmware updates to apply"
  add_note "Some firmware updates only take effect after a reboot — fwupd will say if so."
}

step_gnome_tweaks() {
  if ! command -v gsettings >/dev/null 2>&1; then
    skip "gsettings not available"; return
  fi
  if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    warn "no graphical session detected — run this inside your GNOME session to apply tweaks."
    return
  fi
  gset() {  # schema key value
    if gsettings set "$1" "$2" "$3" 2>/dev/null; then ok "$2 → $3"; else warn "couldn't set $1 $2"; fi
  }
  gset org.gnome.desktop.peripherals.touchpad tap-to-click true
  gset org.gnome.desktop.interface           show-battery-percentage true
  gset org.gnome.desktop.interface           clock-show-weekday true
  gset org.gnome.settings-daemon.plugins.color night-light-enabled true
  gset org.gnome.desktop.wm.preferences      button-layout 'appmenu:minimize,maximize,close'
  gset org.gnome.mutter                       center-new-windows true
}

step_flathub() {
  dnf_install flatpak
  if flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    skip "Flathub remote already present"
  else
    info "adding Flathub remote"
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
  # Fedora ships Flathub filtered to a subset — drop the filter for full access.
  sudo flatpak remote-modify --no-filter --enable flathub || true
  add_note "Flathub enabled — install apps via GNOME Software or 'flatpak install flathub <app-id>'."
}

# ---- step registry ---------------------------------------------------------
# Parallel arrays: key | label | function. Every step runs by default; steps
# that don't apply to this machine (e.g. NVIDIA) detect that and skip themselves.

STEP_KEYS=(   update             dnf               firmware       vscode       chrome          gnome                        gnometweaks            zsh        plugins                   flathub       codecs                steam         nvidia )
STEP_LABELS=( "System update"    "Speed up DNF"    "Firmware updates" "VS Code" "Google Chrome" "GNOME Tweaks & Extensions" "GNOME desktop tweaks" "Zsh"      "Zsh plugins & Starship"  "Flathub"     "Multimedia codecs"   "Steam"       "NVIDIA driver" )
STEP_FUNCS=(  step_system_update step_dnf_speedup  step_firmware  step_vscode  step_chrome     step_gnome                  step_gnome_tweaks      step_zsh   step_zsh_plugins          step_flathub  step_codecs           step_steam    step_nvidia )

# ---- interactive picker ----------------------------------------------------

SELECTED=()

prompt_menu() {
  banner
  printf '%sAll steps run by default.%s Press Enter to run them all, or type a subset.\n\n' \
    "$C_BOLD" "$C_RESET"

  local i n
  for i in "${!STEP_LABELS[@]}"; do
    n=$((i + 1))
    printf '   %s%2d%s  %s\n' "$C_CYAN" "$n" "$C_RESET" "${STEP_LABELS[$i]}"
  done

  printf '\n%sEnter numbers (e.g. 1 4 9), or press Enter for all:%s ' "$C_BOLD" "$C_RESET"

  local input; read -r input || input=''
  SELECTED=()
  if [ -z "$input" ] || [ "$input" = "all" ]; then
    for i in "${!STEP_LABELS[@]}"; do SELECTED+=("$i"); done
  else
    local tok
    for tok in ${input//,/ }; do
      if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#STEP_LABELS[@]}" ]; then
        SELECTED+=("$((tok - 1))")
      else
        warn "ignoring invalid choice: $tok"
      fi
    done
  fi
}

select_all() {
  SELECTED=()
  local i; for i in "${!STEP_LABELS[@]}"; do SELECTED+=("$i"); done
}

confirm_selection() {
  printf '\n%sAbout to run:%s\n' "$C_BOLD" "$C_RESET"
  local i; for i in "${SELECTED[@]}"; do printf '   %s•%s %s\n' "$C_CYAN" "$C_RESET" "${STEP_LABELS[$i]}"; done
  echo
  ask "Proceed?" 1 || { info "Aborted — nothing changed."; exit 0; }
}

# ---- runner ----------------------------------------------------------------

CURRENT_STEP=''
DONE_LABELS=()

on_error() {
  local rc=$?
  printf '\n%s%s✗ Failed%s during: %s%s%s  (exit %d)\n' \
    "$C_BOLD" "$C_RED" "$C_RESET" "$C_BOLD" "${CURRENT_STEP:-startup}" "$C_RESET" "$rc"
  echo "  Fix the issue and re-run ./setup.sh — completed steps will be skipped."
}

cleanup() { [ -n "${SUDO_PID:-}" ] && kill "$SUDO_PID" 2>/dev/null || true; }

run_selected() {
  local total=${#SELECTED[@]} n=0 i
  for i in "${SELECTED[@]}"; do
    n=$((n + 1))
    CURRENT_STEP="${STEP_LABELS[$i]}"
    step_header "$n" "$total" "$CURRENT_STEP"
    "${STEP_FUNCS[$i]}"
    DONE_LABELS+=("$CURRENT_STEP")
  done
}

print_summary() {
  echo; rule
  printf '%s%s✓ Done%s — %d step(s) in %ds\n' "$C_BOLD" "$C_GREEN" "$C_RESET" "${#DONE_LABELS[@]}" "$SECONDS"
  local l; for l in "${DONE_LABELS[@]}"; do printf '   %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$l"; done
  if [ ${#NOTES[@]} -gt 0 ]; then
    printf '\n%sNext steps:%s\n' "$C_BOLD" "$C_RESET"
    local nt; for nt in "${NOTES[@]}"; do printf '   %s•%s %s\n' "$C_YELLOW" "$C_RESET" "$nt"; done
  fi
}

# ---- main ------------------------------------------------------------------

usage() {
  cat <<'EOF'
Fedora Workstation post-install setup.

Usage:
  ./setup.sh            Interactive picker (runs all steps if non-interactive)
  ./setup.sh --yes      Skip all prompts; run all steps
  ./setup.sh --help     Show this help

Steps: update, dnf, firmware, vscode, chrome, gnome, gnome-tweaks, zsh,
       plugins, flathub, codecs, steam, nvidia (auto-skips if no NVIDIA GPU)
Idempotent: re-running skips anything already done.
EOF
}

main() {
  INTERACTIVE=1; [ -t 0 ] || INTERACTIVE=0
  ASSUME_YES=0

  for arg in "$@"; do
    case "$arg" in
      -y|--yes)  ASSUME_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) err "unknown option: $arg"; usage; exit 1 ;;
    esac
  done

  trap on_error ERR
  trap cleanup EXIT

  if [ ! -f /etc/fedora-release ]; then
    warn "This doesn't look like Fedora. Continuing anyway, but commands may fail."
  fi

  # Interactive picker unless --yes or not a terminal; otherwise run everything.
  if [ "$INTERACTIVE" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; then
    prompt_menu
  else
    select_all
  fi

  if [ ${#SELECTED[@]} -eq 0 ]; then
    info "No steps selected — nothing to do."
    exit 0
  fi

  confirm_selection

  info "Caching sudo credentials (keeps them alive for the whole run)..."
  sudo -v
  # Background keep-alive so long installs don't stall on a sudo prompt.
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) &
  SUDO_PID=$!

  run_selected
  print_summary
}

main "$@"
