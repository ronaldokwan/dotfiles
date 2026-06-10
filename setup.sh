#!/usr/bin/env bash
#
# Fedora Workstation (44+) post-install setup.
# Idempotent: safe to run multiple times — each step skips work already done.
#
# Usage:
#   ./setup.sh                 # interactive picker (runs all steps if non-interactive)
#   ./setup.sh --yes           # no prompts; run all steps
#   ./setup.sh vscode chrome   # run only the named steps
#   ./setup.sh --dry-run       # print every change without making it
#   ./setup.sh --help
#
# Steps run independently: one failing step is reported and the rest continue.
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
  local text="$1" width="$2" len pad rpad
  len=${#text}; pad=$(( (width - len) / 2 ))
  # Clamp: if text is wider than the box, a negative field width would make
  # printf left-justify and break the border alignment.
  [ "$pad" -lt 0 ] && pad=0
  rpad=$(( width - len - pad )); [ "$rpad" -lt 0 ] && rpad=0
  printf '%*s%s%*s' "$pad" '' "$text" "$rpad" ''
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

# Per-run scratch dir for state that must survive step subshells (see
# run_selected): deferred notes and reboot reasons are appended to files here
# because steps run in subshells and can't write back to parent arrays.
STATE_DIR=""

# Deferred action items and reboot reasons, shown in the final summary.
add_note()    { [ -n "$STATE_DIR" ] && printf '%s\n' "$1" >> "$STATE_DIR/notes"; }
mark_reboot() { [ -n "$STATE_DIR" ] && printf '%s\n' "$1" >> "$STATE_DIR/reboot"; }

# Fail with a clear message if a required external command is missing.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing required command: $1"; return 1; }
}

# Dry-run: when set, mutating commands are printed instead of executed.
# Read-only probes (rpm -q, lspci, command -v, ...) still run so control flow
# is realistic. Default off; enabled by --dry-run.
DRY_RUN=0

# Run a command, or just print it when in dry-run mode. Use this only for
# state-changing commands — never for the detection probes that decide flow.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  [dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
  else
    "$@"
  fi
}

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
  if [ -e "$file" ] && grep -qxF -- "$line" "$file"; then
    skip "already in ${file/#$HOME/\~}: $line"
  elif [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  [dry-run]%s append to %s: %s\n' "$C_YELLOW" "$C_RESET" "${file/#$HOME/\~}" "$line"
  else
    touch "$file"
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
  run sudo dnf install -y \
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
    run sudo dnf install -y "${missing[@]}"
  fi
}

# ---- steps -----------------------------------------------------------------

step_system_update() {
  run sudo dnf upgrade --refresh -y
  add_note "If the kernel was updated, reboot before NVIDIA or other kernel-module steps."
}

step_dnf_speedup() {
  local conf=/etc/dnf/dnf.conf
  for kv in "max_parallel_downloads=10" "defaultyes=True"; do
    local key="${kv%%=*}"
    if sudo grep -q "^${key}=" "$conf"; then
      skip "$key already set in $conf"
    elif [ "$DRY_RUN" -eq 1 ]; then
      printf '%s  [dry-run]%s append to %s: %s\n' "$C_YELLOW" "$C_RESET" "$conf" "$kv"
    else
      echo "$kv" | sudo tee -a "$conf" >/dev/null
      ok "added to $conf: $kv"
    fi
  done
}

step_vscode() {
  if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
    info "importing Microsoft repo"
    run sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    run sudo sh -c 'printf "%s\n" "[code]" "name=Visual Studio Code" "baseurl=https://packages.microsoft.com/yumrepos/vscode" "enabled=1" "gpgcheck=1" "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
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
    run sudo dnf install -y --enablerepo=google-chrome google-chrome-stable
  fi
}

step_gnome() {
  dnf_install gnome-tweaks gnome-extensions-app
  add_note "Browse/toggle GNOME extensions at https://extensions.gnome.org/ (install the browser connector first)."
}

step_zsh() {
  dnf_install zsh

  local zsh_path login_shell
  zsh_path="$(command -v zsh)"
  # Read the login shell from /etc/passwd, not $SHELL — $SHELL reflects the
  # shell that started this session, which may differ from the account default.
  login_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$login_shell" = "$zsh_path" ]; then
    skip "zsh is already the default shell"
  else
    # Run chsh via cached sudo with an explicit target user: a plain `chsh`
    # authenticates the calling user through PAM, which blocks an unattended
    # (--yes) run. Going through sudo reuses the credentials cached in main().
    info "setting zsh as default shell"
    if run sudo chsh -s "$zsh_path" "$USER"; then
      add_note "Log out and back in for zsh to become your default shell."
    else
      warn "chsh failed — set it manually with: sudo chsh -s $zsh_path $USER"
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

# Pinned starship release + per-arch SHA-256 of the release tarball. Verifying a
# known hash is why we download the binary directly instead of piping the
# upstream install script into a shell. To bump: pick a new version below and
# update BOTH hashes from the release's *.tar.gz.sha256 sidecars at
# https://github.com/starship/starship/releases
STARSHIP_VERSION="v1.25.1"
declare -A STARSHIP_TARGET=( [x86_64]="x86_64-unknown-linux-gnu" [aarch64]="aarch64-unknown-linux-musl" )
declare -A STARSHIP_SHA256=(
  [x86_64]="4488c11ca632327d1f1f16fb2f102c0646094c35479cd5435991385da43c61ac"
  [aarch64]="01517aab398959ea9ea73bdb4f032ea4dbb51dff5c8e5eb05b4a1b9b7ab872b8"
)

# Download the pinned starship tarball, verify its SHA-256, and install the
# binary to /usr/local/bin. Fails closed on download error or hash mismatch.
install_starship() {
  local arch target sha url tmp
  arch="$(uname -m)"
  target="${STARSHIP_TARGET[$arch]:-}"; sha="${STARSHIP_SHA256[$arch]:-}"
  if [ -z "$target" ] || [ -z "$sha" ]; then
    err "no pinned starship build for arch '$arch' — install it manually and re-run"
    return 1
  fi
  url="https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/starship-${target}.tar.gz"

  if [ "$DRY_RUN" -eq 1 ]; then
    run "curl -fsSL $url | verify sha256 $sha | sudo install -m755 starship /usr/local/bin"
    return 0
  fi

  tmp="$(mktemp -d)"
  info "downloading starship ${STARSHIP_VERSION} (${target})"
  if ! curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp/starship.tar.gz"; then
    err "failed to download starship"; rm -rf "$tmp"; return 1
  fi
  if ! printf '%s  %s\n' "$sha" "$tmp/starship.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
    err "starship checksum mismatch — refusing to install (expected $sha)"; rm -rf "$tmp"; return 1
  fi
  ok "checksum verified"
  tar -xzf "$tmp/starship.tar.gz" -C "$tmp" starship
  sudo install -m755 "$tmp/starship" /usr/local/bin/starship
  rm -rf "$tmp"
  ok "starship installed to /usr/local/bin"
}

step_zsh_plugins() {
  require_cmd git || return 1        # plugins are git clones
  require_cmd curl || return 1       # starship download
  require_cmd sha256sum || return 1  # starship verification

  clone_if_missing() {
    local url="$1" dir="$2"
    if [ -d "$dir" ]; then skip "${dir/#$HOME/\~} already cloned"; else
      info "cloning $url"
      run git clone --depth 1 "$url" "$dir"
    fi
  }
  clone_if_missing https://github.com/zsh-users/zsh-autosuggestions      "$HOME/.zsh/zsh-autosuggestions"
  clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting  "$HOME/.zsh/zsh-syntax-highlighting"

  if command -v starship >/dev/null 2>&1; then
    skip "starship already installed"
  else
    install_starship
  fi

  # Wire up ~/.zshrc — order matters: autosuggestions, then highlighting, then starship.
  local zshrc="$HOME/.zshrc"
  ensure_line '# Autosuggestions'                                                 "$zshrc"
  ensure_line 'source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh'         "$zshrc"
  ensure_line '# Syntax highlighting (must come after autosuggestions)'           "$zshrc"
  ensure_line 'source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' "$zshrc"
  ensure_line '# Starship prompt (always last)'                                   "$zshrc"
  # shellcheck disable=SC2016  # intentional: write the literal line, don't expand it now
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
  run sudo dnf upgrade --refresh -y

  ensure_rpmfusion
  dnf_install akmod-nvidia

  # CUDA is a large optional dependency (enables nvidia-smi / compute). Default
  # to installing it so unattended (--yes) runs keep their previous behaviour,
  # but let an interactive user opt out.
  if ask "Also install CUDA support (xorg-x11-drv-nvidia-cuda, ~large download)?" 1; then
    dnf_install xorg-x11-drv-nvidia-cuda
  else
    skip "CUDA packages not installed"
  fi

  warn "akmod is building the kernel module in the background (~5 min)."
  add_note "NVIDIA: wait for the module to build ('modinfo -F version nvidia' prints a version), then reboot and check 'nvidia-smi'."
  mark_reboot "NVIDIA driver installed — reboot once the kernel module finishes building."
}

step_codecs() {
  # Fedora ships without patent-encumbered codecs — needed for video playback
  # and hardware decode. Lives in RPM Fusion.
  ensure_rpmfusion
  info "installing multimedia group"
  run sudo dnf group install -y multimedia

  # Swap the patent-stripped ffmpeg-free for the full RPM Fusion ffmpeg. Done
  # AFTER the group install, since that group can pull ffmpeg-free back in —
  # swapping first would leave the crippled build on a fresh system.
  if pkg_installed ffmpeg-free; then
    info "swapping in full ffmpeg"
    run sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
  elif pkg_installed ffmpeg; then
    skip "full ffmpeg already in place"
  else
    warn "neither ffmpeg nor ffmpeg-free present after group install"
  fi

  # Hardware video decode, per GPU vendor.
  local gpus; gpus="$(lspci | grep -Ei 'vga|3d|display' || true)"
  if grep -qi nvidia <<<"$gpus"; then
    dnf_install libva-nvidia-driver   # NVIDIA: VA-API via NVDEC
  fi
  if grep -qiE 'amd|ati|radeon' <<<"$gpus"; then
    # Fedora's stock mesa drivers have H.264/H.265 stripped (patents);
    # the RPM Fusion "freeworld" builds re-enable them.
    if pkg_installed mesa-va-drivers; then
      info "swapping in mesa-va freeworld driver (AMD hardware decode)"
      run sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    else
      skip "mesa-va-drivers already freeworld"
    fi
    if pkg_installed mesa-vdpau-drivers; then
      info "swapping in mesa-vdpau freeworld driver"
      run sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    else
      skip "mesa-vdpau-drivers already freeworld"
    fi
  fi
}

step_steam() {
  ensure_rpmfusion
  dnf_install steam
}

step_firmware() {
  dnf_install fwupd
  # fwupdmgr exit codes: 0 = success, 2 = nothing to do, anything else = real error.
  local rc

  info "refreshing firmware metadata from LVFS"
  rc=0
  if [ "$DRY_RUN" -eq 1 ]; then
    run sudo fwupdmgr refresh --force
  else
    sudo fwupdmgr refresh --force || rc=$?
  fi
  case "$rc" in
    0) ok "metadata refreshed" ;;
    2) skip "metadata already up to date" ;;
    *) err "fwupdmgr refresh failed (exit $rc)"; return "$rc" ;;
  esac

  info "applying firmware updates (if any)"
  rc=0
  if [ "$DRY_RUN" -eq 1 ]; then
    run sudo fwupdmgr update -y
  else
    sudo fwupdmgr update -y || rc=$?
  fi
  case "$rc" in
    0) ok "firmware updates applied"
       mark_reboot "Firmware updates were staged — reboot to let fwupd apply them." ;;
    2) skip "no firmware updates to apply" ;;
    *) err "fwupdmgr update failed (exit $rc)"; return "$rc" ;;
  esac
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
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '%s  [dry-run]%s gsettings set %s %s %s\n' "$C_YELLOW" "$C_RESET" "$1" "$2" "$3"
      return
    fi
    local err
    if err="$(gsettings set "$1" "$2" "$3" 2>&1)"; then
      ok "$2 → $3"
    else
      warn "couldn't set $1 $2: $err"
    fi
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
    run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
  # Fedora ships Flathub filtered to a subset — drop the filter for full access.
  run sudo flatpak remote-modify --no-filter --enable flathub
  add_note "Flathub enabled — install apps via GNOME Software or 'flatpak install flathub <app-id>'."
}

# ---- step registry ---------------------------------------------------------
# Parallel arrays: key | label | function. Every step runs by default; steps
# that don't apply to this machine (e.g. NVIDIA) detect that and skip themselves.

STEP_KEYS=(   update             dnf               firmware       vscode       chrome          gnome                        gnome-tweaks           zsh        plugins                   flathub       codecs                steam         nvidia )
STEP_LABELS=( "System update"    "Speed up DNF"    "Firmware updates" "VS Code" "Google Chrome" "GNOME Tweaks & Extensions" "GNOME desktop tweaks" "Zsh"      "Zsh plugins & Starship"  "Flathub"     "Multimedia codecs"   "Steam"       "NVIDIA driver" )
STEP_FUNCS=(  step_system_update step_dnf_speedup  step_firmware  step_vscode  step_chrome     step_gnome                  step_gnome_tweaks      step_zsh   step_zsh_plugins          step_flathub  step_codecs           step_steam    step_nvidia )

# Resolve a step key (e.g. "vscode") to its array index. Echoes the index and
# returns 0 on match; returns 1 if the key is unknown.
key_to_index() {
  local k="$1" i
  for i in "${!STEP_KEYS[@]}"; do
    [ "${STEP_KEYS[$i]}" = "$k" ] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

# Drop duplicate indices from SELECTED, preserving first-seen order.
dedup_selected() {
  local -A seen; local out=() i
  for i in "${SELECTED[@]}"; do
    if [ -z "${seen[$i]:-}" ]; then seen[$i]=1; out+=("$i"); fi
  done
  SELECTED=("${out[@]}")
}

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
    dedup_selected
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
FAILED_STEPS=()

# Fires only for failures outside a step (startup, picker, sudo bootstrap) —
# inside run_selected the ERR trap is cleared and per-step failure is handled.
on_error() {
  local rc=$?
  printf '\n%s%s✗ Failed%s during: %s%s%s  (exit %d)\n' \
    "$C_BOLD" "$C_RED" "$C_RESET" "$C_BOLD" "${CURRENT_STEP:-startup}" "$C_RESET" "$rc"
  echo "  Fix the issue and re-run ./setup.sh — completed steps will be skipped."
}

cleanup() {
  [ -n "${SUDO_PID:-}" ] && kill "$SUDO_PID" 2>/dev/null
  [ -n "$STATE_DIR" ] && rm -rf "$STATE_DIR"
  return 0
}

run_selected() {
  local total=${#SELECTED[@]} n=0 i rc
  # Handle per-step failure here instead of letting on_error abort the run.
  # The ERR trap fires independently of set -e, so it must be cleared for the
  # loop and restored afterwards.
  trap - ERR
  for i in "${SELECTED[@]}"; do
    n=$((n + 1))
    CURRENT_STEP="${STEP_LABELS[$i]}"
    step_header "$n" "$total" "$CURRENT_STEP"
    # Run each step in an isolated subshell so one failure doesn't abort the
    # rest. set -e inside keeps the step atomic; set +e outside lets the parent
    # capture the exit code and move on. add_note / mark_reboot write to files
    # precisely because this subshell can't mutate parent arrays.
    rc=0
    set +e
    ( set -e; "${STEP_FUNCS[$i]}" )
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      DONE_LABELS+=("$CURRENT_STEP")
    else
      FAILED_STEPS+=("$CURRENT_STEP")
      err "step '$CURRENT_STEP' failed (exit $rc) — continuing with remaining steps"
    fi
  done
  trap on_error ERR
}

print_summary() {
  echo; rule
  printf '%s%s✓ Done%s — %d ok, %d failed, in %ds\n' \
    "$C_BOLD" "$C_GREEN" "$C_RESET" "${#DONE_LABELS[@]}" "${#FAILED_STEPS[@]}" "$SECONDS"
  local l
  for l in "${DONE_LABELS[@]}";  do printf '   %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$l"; done
  for l in "${FAILED_STEPS[@]}"; do printf '   %s✗%s %s\n' "$C_RED"   "$C_RESET" "$l"; done

  if [ -s "$STATE_DIR/reboot" ]; then
    printf '\n%s%s⚠ Reboot recommended:%s\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
    while IFS= read -r r; do printf '   %s•%s %s\n' "$C_YELLOW" "$C_RESET" "$r"; done < "$STATE_DIR/reboot"
  fi
  if [ -s "$STATE_DIR/notes" ]; then
    printf '\n%sNext steps:%s\n' "$C_BOLD" "$C_RESET"
    while IFS= read -r nt; do printf '   %s•%s %s\n' "$C_YELLOW" "$C_RESET" "$nt"; done < "$STATE_DIR/notes"
  fi
  if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
    printf '\n%sRe-run ./setup.sh to retry the failed step(s) — anything done is skipped.%s\n' "$C_DIM" "$C_RESET"
  fi
}

# ---- main ------------------------------------------------------------------

usage() {
  cat <<'EOF'
Fedora Workstation post-install setup.

Usage:
  ./setup.sh                 Interactive picker (runs all steps if non-interactive)
  ./setup.sh --yes           Skip all prompts; run all steps
  ./setup.sh vscode chrome   Run only the named steps
  ./setup.sh --dry-run       Print every change without making it
  ./setup.sh --help          Show this help

Steps: update, dnf, firmware, vscode, chrome, gnome, gnome-tweaks, zsh,
       plugins, flathub, codecs, steam, nvidia (auto-skips if no NVIDIA GPU)
Idempotent: re-running skips anything already done.
EOF
}

main() {
  # Must run as the target user, not root: this script calls sudo itself for
  # the system steps, while the per-user steps (~/.zshrc, ~/.zsh clones,
  # gsettings, chsh) must land in the real user's account. Running the whole
  # thing under sudo would write them to /root instead.
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    err "Don't run this script as root or with sudo — it calls sudo itself when needed."
    exit 1
  fi

  # The step registry is three parallel arrays — a missed entry would run the
  # wrong function under the wrong label. Fail loudly if they ever drift.
  if [ "${#STEP_KEYS[@]}" -ne "${#STEP_LABELS[@]}" ] || [ "${#STEP_LABELS[@]}" -ne "${#STEP_FUNCS[@]}" ]; then
    err "step registry arrays are out of sync (keys=${#STEP_KEYS[@]} labels=${#STEP_LABELS[@]} funcs=${#STEP_FUNCS[@]})"
    exit 1
  fi

  INTERACTIVE=1; [ -t 0 ] || INTERACTIVE=0
  ASSUME_YES=0

  local cli_steps=()
  for arg in "$@"; do
    case "$arg" in
      -y|--yes)     ASSUME_YES=1 ;;
      -n|--dry-run) DRY_RUN=1 ;;
      -h|--help)    usage; exit 0 ;;
      -*) err "unknown option: $arg"; usage; exit 1 ;;
      *) cli_steps+=("$arg") ;;
    esac
  done

  trap on_error ERR
  trap cleanup EXIT

  if [ ! -f /etc/fedora-release ]; then
    warn "This doesn't look like Fedora. Continuing anyway, but commands may fail."
  fi

  # Step names on the command line take precedence over the picker.
  if [ ${#cli_steps[@]} -gt 0 ]; then
    SELECTED=()
    local s idx
    for s in "${cli_steps[@]}"; do
      if idx="$(key_to_index "$s")"; then
        SELECTED+=("$idx")
      else
        err "unknown step: $s"; usage; exit 1
      fi
    done
    dedup_selected
  # Interactive picker unless --yes or not a terminal; otherwise run everything.
  elif [ "$INTERACTIVE" -eq 1 ] && [ "$ASSUME_YES" -eq 0 ]; then
    prompt_menu
  else
    select_all
  fi

  if [ ${#SELECTED[@]} -eq 0 ]; then
    info "No steps selected — nothing to do."
    exit 0
  fi

  confirm_selection

  # Dry-run needs no privileges — skip the sudo prompt and keep-alive entirely.
  if [ "$DRY_RUN" -eq 1 ]; then
    warn "DRY RUN — printing changes only; nothing will be installed or modified."
  else
    info "Caching sudo credentials (keeps them alive for the whole run)..."
    sudo -v
    # Background keep-alive so long installs don't stall on a sudo prompt.
    # Guard sudo -n true: on failure (expired creds, PAM policy) warn and stop
    # rather than letting the inherited set -e silently kill the loop.
    ( while kill -0 "$$" 2>/dev/null; do
        sudo -n true 2>/dev/null || { warn "sudo keep-alive failed — you may be prompted again"; break; }
        sleep 50
      done ) &
    SUDO_PID=$!
  fi

  # Scratch dir for notes / reboot reasons emitted from step subshells; removed
  # by cleanup() on exit.
  STATE_DIR="$(mktemp -d)"

  run_selected
  print_summary
}

main "$@"
