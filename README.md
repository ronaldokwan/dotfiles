# Fedora Setup

A post-install setup guide for **Fedora Workstation 44+** that takes a fresh install from boot to a complete daily-driver environment: system updates, essential applications (VS Code, Chrome, Steam), a Zsh + Starship shell, GNOME tweaks, multimedia codecs, and the NVIDIA driver.

Every step is a plain `dnf` or `gsettings` command that can be reviewed before it is run.

## Prerequisites

- Fedora Workstation 44 or newer
- A user account with `sudo` privileges
- An active internet connection

## Installation

Install `git` if it is not already present, then clone the repository and change into it:

```bash
sudo dnf install -y git && git clone https://github.com/ronaldokwan/dotfiles.git && cd dotfiles
```

Work through the sections below in order. Each section is self-contained, so any that do not apply may be skipped.

> [!NOTE]
> Run these commands as your normal user. `sudo` is shown explicitly on the steps that require root, so per-user changes — `~/.zshrc`, your default shell, and GNOME settings — apply to your account rather than root's.

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
11. [RPM Fusion](#11-rpm-fusion) — required for 12–14
12. [Multimedia codecs](#12-multimedia-codecs)
13. [Steam](#13-steam)
14. [NVIDIA driver](#14-nvidia-driver)

---

## 1. System update

```bash
sudo dnf upgrade --refresh
```

> [!NOTE]
> `upgrade` is the modern DNF 5 verb (`update` still works as an alias). Reboot if the kernel was updated.

## 2. Speed up DNF

DNF downloads packages **3 at a time** by default and isn't set in Fedora's stock config. Raising the limit speeds up large transactions. Check the value DNF actually uses:

```bash
# DNF 4 (Fedora ≤ 40)
python3 -c "import dnf; print(dnf.Base().conf.max_parallel_downloads)"

# DNF 5 (Fedora 41+)
dnf config-manager --dump 2>/dev/null | grep max_parallel_downloads
```

If it reports `3` (the default), bump it. Edit the config and add the lines if they aren't already there (`defaultyes` auto-confirms install prompts):

```bash
sudo nano /etc/dnf/dnf.conf
```

```ini
max_parallel_downloads=10
defaultyes=True
```

> [!NOTE]
> Leave `defaultyes=True` out if you'd rather confirm each transaction manually — it makes `dnf` proceed without the `[y/N]` prompt.

## 3. Firmware updates

Pull UEFI / SSD / peripheral firmware from [LVFS](https://fwupd.org/) and apply it (`fwupd` ships with Workstation):

```bash
sudo fwupdmgr refresh --force
sudo fwupdmgr update
```

> [!NOTE]
> Some updates only apply on the next boot — fwupd will tell you if a reboot is needed.

## 4. VS Code

Import Microsoft's repo and install via DNF (gets automatic updates, unlike the download):

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'printf "%s\n" "[code]" "name=Visual Studio Code" "baseurl=https://packages.microsoft.com/yumrepos/vscode" "enabled=1" "gpgcheck=1" "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install code
```

Verify:

```bash
code --version
```

> [!TIP]
> Alternatively, download the `.rpm` from <https://code.visualstudio.com/>. The repository method above is preferred, as it receives automatic updates.

## 5. Google Chrome

Install Fedora's third-party repo definitions, then install Chrome — enabling its repo just for that transaction (Chrome then adds its own repo for future updates):

```bash
sudo dnf install fedora-workstation-repositories
sudo dnf install --enablerepo=google-chrome google-chrome-stable
```

Verify:

```bash
google-chrome --version
```

> [!NOTE]
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

> [!NOTE]
> Run these inside your GNOME session (they talk to the running desktop). Adjust to taste — each line is independent.

## 8. Zsh

```bash
sudo dnf install zsh
```

Make it your default shell:

```bash
chsh -s "$(which zsh)"
```

Log out and back in, then confirm the change took effect:

```bash
echo $SHELL        # should print /usr/bin/zsh
```

On first launch, zsh creates `~/.zshrc`.

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

> [!WARNING]
> Piping a remote script into a shell is trust-on-first-use. If you'd rather not, download a pinned release tarball from the [Starship releases page](https://github.com/starship/starship/releases), verify its SHA-256 against the published `*.tar.gz.sha256` sidecar, and install the binary to `/usr/local/bin` yourself.

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

> [!IMPORTANT]
> The next three steps — **Multimedia codecs (12)**, **Steam (13)**, and **NVIDIA driver (14)** — all install from RPM Fusion. Enable it here first, then continue top to bottom.

A shared third-party repo that several steps depend on — the NVIDIA driver, multimedia codecs, and Steam all live here, not in Fedora's default repos. Enable it once:

```bash
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

> [!NOTE]
> Re-running is safe: `dnf install` is a no-op on the `*-release` packages when they are already installed.

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

> [!NOTE]
> AMD GPUs don't need a proprietary driver — the open-source `amdgpu`/Mesa stack ships in Fedora's default repos and works out of the box. RPM Fusion is only needed here for the codec-enabled `-freeworld` drivers.

## 13. Steam

Enable [RPM Fusion](#11-rpm-fusion) if you haven't, then:

```bash
sudo dnf install steam
```

> [!TIP]
> GUI alternative: **Software → Enable third-party repositories → search "Steam"**.

## 14. NVIDIA driver

Only needed for NVIDIA GPUs — AMD/Intel use the open-source stack out of the box. The steps below are for NVIDIA hardware.

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

**Wait for the kernel module to build** — `akmod` builds it in the background (~5 min). Check progress:

```bash
modinfo -F version nvidia
```

- Prints a version (e.g. `560.35.03`) → build finished ✅
- Errors out → not done yet, wait longer.

> [!IMPORTANT]
> Don't reboot until `modinfo` prints a version — rebooting mid-build can drop you to a black screen with no working driver.

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

## Finishing up

That's the full setup. A few steps need a reboot to fully take effect — do a final reboot if you ran any of them:

- **System update (1)** — if a new kernel was installed
- **Firmware updates (3)** — staged updates apply during boot
- **Zsh (8)** — log out and back in for the default-shell change
- **NVIDIA driver (14)** — required after the module builds

```bash
sudo reboot
```

After rebooting, you should have a fully updated system with your applications, shell, and drivers in place.

## License

Released under the [MIT License](LICENSE).
