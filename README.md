# Fedora Setup

Post-install setup notes for Fedora Workstation (44+). Run through them top to bottom on a fresh install.

## Get the files

Clone the repo and `cd` into it (install `git` first if a fresh system doesn't have it):

```bash
sudo dnf install -y git && git clone https://github.com/ronaldokwan/dotfiles.git && cd dotfiles && ./setup.sh
```

## Automated setup

Most of this guide is scripted in [`setup.sh`](setup.sh). Run it with no arguments for an interactive picker — choose which steps to run, watch per-step progress, and get a summary of follow-up actions at the end. It's idempotent: safe to re-run; each step skips work already done. The NVIDIA step detects your GPU and only installs the driver on NVIDIA hardware.

```bash
./setup.sh                 # interactive picker (all steps by default)
./setup.sh --yes           # no prompts; run all steps
./setup.sh vscode chrome   # run only the named steps
./setup.sh --dry-run       # print every change without making it
./setup.sh --help
```

Run it as your normal user — **not** with `sudo`. The script calls `sudo` itself only for the steps that need root, so the per-user changes (your `~/.zshrc`, shell, GNOME settings) land in your account rather than root's. Available step names: `update`, `dnf`, `firmware`, `vscode`, `chrome`, `gnome`, `gnome-tweaks`, `zsh`, `plugins`, `flathub`, `codecs`, `steam`, `nvidia`.

### Running it

Running `./setup.sh` (as shown above) gives you a numbered menu. **Press Enter to run everything**, or type a subset like `1 4 9` and press Enter to run only those steps. Then confirm with `y`:

```console
  ┌────────────────────────────────────────┐
  │              Fedora Setup              │
  │  post-install setup · Workstation 44+  │
  └────────────────────────────────────────┘

All steps run by default. Press Enter to run them all, or type a subset.

    1  System update
    2  Speed up DNF
    3  Firmware updates
    ⋮
   12  Steam
   13  NVIDIA driver

Enter numbers (e.g. 1 4 9), or press Enter for all:        ⏎
                                                           (Enter = all)
About to run:
   • System update
   • Speed up DNF
   ⋮

Proceed? [y/N] y                                           ← type y, then Enter

==> Caching sudo credentials (keeps them alive for the whole run)...
[sudo] password for you: ••••                              ← your login password

[1/13] System update
==> ...
```

- **`⏎`** means press <kbd>Enter</kbd>. Pressing it on an empty line selects every step.
- You're asked for your password once (for `sudo`); it's cached for the whole run.
- Each step prints `[n/13]` progress, and a summary with any follow-up actions appears at the end.
- **One failing step doesn't stop the rest.** Each step runs independently; failures are collected and listed at the end (`✓ Done — N ok, M failed`), so you can fix and re-run just those.
- The summary flags a **⚠ Reboot recommended** when a step needs one (NVIDIA driver, staged firmware).
- Safe to **re-run** anytime — finished work is detected and skipped.

Want to see exactly what it would do without touching anything? Run `./setup.sh --dry-run` — every install, swap, file edit, and `gsettings` call is printed with a `[dry-run]` prefix instead of being executed.

Prefer to understand each step first, or only want some of them? The sections below are the manual equivalents.

## Contents

1. [System update](#1-system-update)
2. [Speed up DNF](#2-speed-up-dnf)
3. [Firmware updates](#3-firmware-updates)
4. [VS Code](#4-vs-code)
5. [Google Chrome](#5-google-chrome)
6. [GNOME Tweaks & Extensions](#6-gnome-tweaks--extensions)
7. [GNOME desktop tweaks](#7-gnome-desktop-tweaks)
8. [Zsh](#8-zsh)
9. [Zsh plugins & Starship prompt](#9-zsh-plugins--starship-prompt)
10. [Flathub](#10-flathub)
11. [RPM Fusion](#11-rpm-fusion)
12. [Multimedia codecs](#12-multimedia-codecs)
13. [Steam](#13-steam)
14. [NVIDIA driver](#14-nvidia-driver)

---

## 1. System update

```bash
sudo dnf upgrade --refresh
```

> `upgrade` is the modern DNF 5 verb (`update` still works as an alias). Reboot if the kernel was updated.

## 2. Speed up DNF

Enable parallel downloads and default-yes prompts:

```bash
sudo nano /etc/dnf/dnf.conf
```

Add:

```ini
max_parallel_downloads=10
defaultyes=True
```

## 3. Firmware updates

Pull UEFI / SSD / peripheral firmware from [LVFS](https://fwupd.org/) and apply it (`fwupd` ships with Workstation):

```bash
sudo fwupdmgr refresh --force
sudo fwupdmgr update
```

> Some updates only apply on the next boot — fwupd will tell you if a reboot is needed.

## 4. VS Code

Import Microsoft's repo and install via DNF (gets automatic updates, unlike the download):

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'printf "%s\n" "[code]" "name=Visual Studio Code" "baseurl=https://packages.microsoft.com/yumrepos/vscode" "enabled=1" "gpgcheck=1" "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install code
```

> Prefer a one-liner? Download the `.rpm` from <https://code.visualstudio.com/> — but the repo method keeps it updated.

## 5. Google Chrome

Install Fedora's third-party repo definitions, then install Chrome — enabling its repo just for that transaction (Chrome then adds its own repo for future updates):

```bash
sudo dnf install fedora-workstation-repositories
sudo dnf install --enablerepo=google-chrome google-chrome-stable
```

> `--enablerepo` avoids needing the `config-manager` dnf plugin, which isn't always installed on DNF 5. Or grab the `.rpm` directly from <https://www.google.com/chrome/>.

## 6. GNOME Tweaks & Extensions

```bash
sudo dnf install gnome-tweaks gnome-extensions-app
```

Browse and toggle extensions at <https://extensions.gnome.org/> (install the browser connector first).

## 7. GNOME desktop tweaks

A few common preferences, set from the terminal via `gsettings` (no logout needed):

```bash
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.mutter center-new-windows true
```

> Run these inside your GNOME session (they talk to the running desktop). Adjust to taste — each line is independent.

## 8. Zsh

```bash
sudo dnf install zsh
```

Make it your default shell:

```bash
chsh -s "$(which zsh)"
```

Log out and back in. On first launch, zsh creates `~/.zshrc`.

### Aliases

Add your aliases to `~/.zshrc`:

```bash
# Aliases
alias zshrc="code ~/.zshrc"
alias reload="source ~/.zshrc"
alias c="clear"
alias update="sudo dnf upgrade --refresh"
```

Reload:

```bash
source ~/.zshrc
```

## 9. Zsh plugins & Starship prompt

### Install plugins

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
```

### Install Starship

The quick upstream method pipes the install script straight into a shell:

```bash
curl -sS https://starship.rs/install.sh | sh
```

> `setup.sh` does **not** do this. Instead it downloads a pinned release tarball, verifies its SHA-256 against a hash baked into the script (failing closed on mismatch), and installs the binary to `/usr/local/bin` — avoiding trust-on-first-use in the piped installer. To bump the version, update `STARSHIP_VERSION` and the per-arch hashes near the top of `step_zsh_plugins` from the release's `*.tar.gz.sha256` sidecars.

### Wire it up in `~/.zshrc`

Order matters:

```bash
# Autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Syntax highlighting (must come after autosuggestions)
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Starship prompt (always last)
eval "$(starship init zsh)"
```

Reload:

```bash
source ~/.zshrc
```

### Using the plugins

**Autosuggestions** — greyed-out suggestions appear from history as you type:

| Action | Key |
| --- | --- |
| Accept full suggestion | `→` or `End` |
| Accept one word | `Ctrl + F` |
| Ignore | Keep typing |

**Syntax highlighting** — valid commands turn green, invalid ones red.

**Starship** — configure via `~/.config/starship.toml`:

```bash
# Apply a preset to get started
starship preset gruvbox-rainbow -o ~/.config/starship.toml

# Browse all presets
starship preset --list
```

## 10. Flathub

Fedora's Flatpak remote is **filtered** by default, so many apps (Spotify, Discord, OBS, …) aren't installable until you add the full Flathub remote and drop the filter:

```bash
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak remote-modify --no-filter --enable flathub
```

Then install apps via GNOME Software or:

```bash
flatpak install flathub <app-id>
```

## 11. RPM Fusion

A shared third-party repo that several steps depend on — the NVIDIA driver, multimedia codecs, and Steam all live here, not in Fedora's default repos. Enable it once:

```bash
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

> Already enabled? `dnf install` is a no-op on the `*-release` packages, so re-running is harmless.

## 12. Multimedia codecs

Fedora ships without patent-encumbered codecs, so out of the box you get broken or choppy video in browsers, no H.264/H.265 hardware decode, and missing formats in media players. The codecs live in RPM Fusion.

Enable [RPM Fusion](#11-rpm-fusion) if you haven't, then install the group **first** and swap in full ffmpeg **after** — the `multimedia` group can otherwise pull `ffmpeg-free` back in, leaving you with the patent-stripped build:

```bash
sudo dnf group install multimedia
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
```

Then enable hardware video decode for your GPU:

**NVIDIA:**

```bash
sudo dnf install libva-nvidia-driver
```

**AMD / Radeon** — Fedora's stock Mesa drivers have H.264/H.265 stripped (patents); the RPM Fusion "freeworld" builds re-enable them:

```bash
sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld
sudo dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
```

> AMD GPUs don't need a proprietary driver — the open-source `amdgpu`/Mesa stack ships in Fedora's default repos and works out of the box. RPM Fusion is only needed here for the codec-enabled `-freeworld` drivers.

## 13. Steam

Enable [RPM Fusion](#11-rpm-fusion) if you haven't, then:

```bash
sudo dnf install steam
```

> GUI alternative: **Software → Enable third-party repositories → search "Steam"**.

## 14. NVIDIA driver

Only needed for NVIDIA GPUs — AMD/Intel use the open-source stack out of the box. The script detects this automatically and skips the driver on non-NVIDIA machines; the manual steps below are for NVIDIA hardware.

### Part 1 — Check what you have

**Identify your GPU:**

```bash
lspci | grep -i -e vga -e 3d
```

**Check the driver in use:**

```bash
lspci -k | grep -A 3 -i "vga\|3d"
```

- `Kernel driver in use: nouveau` → open-source driver (proprietary **not** installed)
- `Kernel driver in use: nvidia` → proprietary driver already active

**Test the proprietary driver:**

```bash
nvidia-smi
```

- Prints a GPU table → **already working, you're done.**
- `command not found` / communication error → continue to Part 2.

### Part 2 — Install the driver

**Update first** (the driver must match your running kernel):

```bash
sudo dnf upgrade --refresh
```

If the kernel updated, **reboot before continuing**.

**Enable [RPM Fusion](#11-rpm-fusion)** if you haven't — the driver lives there.

**Install the driver (and optional CUDA support):**

```bash
sudo dnf install akmod-nvidia
sudo dnf install xorg-x11-drv-nvidia-cuda   # optional: CUDA / nvidia-smi
```

**Wait for the kernel module to build** ⚠️ — `akmod` builds it in the background (~5 min). Check progress:

```bash
modinfo -F version nvidia
```

- Prints a version (e.g. `560.35.03`) → build finished ✅
- Errors out → not done yet, wait longer.

**Reboot:**

```bash
sudo reboot
```

### Part 3 — Verify

```bash
nvidia-smi                              # should show the GPU table
lspci -k | grep -A 3 -i "vga\|3d"       # "Kernel driver in use:" should say nvidia
lsmod | grep nvidia                     # nvidia, nvidia_modeset, nvidia_drm, nvidia_uvm
```

---

## Development

The script is linted in CI on every push and pull request (see [`.github/workflows/lint.yml`](.github/workflows/lint.yml)), which runs:

```bash
bash -n setup.sh      # syntax check
shellcheck setup.sh   # static analysis
```

To run the same checks locally before committing:

```bash
bash -n setup.sh
shellcheck setup.sh           # dnf install ShellCheck  (or: brew install shellcheck)
./setup.sh --dry-run          # trace every action without changing anything
```
