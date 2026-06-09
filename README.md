# Fedora Setup

Post-install setup notes for Fedora Workstation (44+). Run through these top to bottom on a fresh install.

## Contents

1. [System update](#1-system-update)
2. [Speed up DNF](#2-speed-up-dnf)
3. [VS Code](#3-vs-code)
4. [Google Chrome](#4-google-chrome)
5. [GNOME Tweaks & Extensions](#5-gnome-tweaks--extensions)
6. [Zsh](#6-zsh)
7. [Zsh plugins & Starship prompt](#7-zsh-plugins--starship-prompt)
8. [NVIDIA driver (optional)](#8-nvidia-driver-optional)
9. [Steam](#9-steam)

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

## 3. VS Code

Import Microsoft's repo and install via DNF (gets automatic updates, unlike the download):

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf install code
```

> Prefer a one-liner? Download the `.rpm` from <https://code.visualstudio.com/> — but the repo method keeps it updated.

## 4. Google Chrome

Enable the third-party repos (Fedora prompts for this on first boot), then:

```bash
sudo dnf install fedora-workstation-repositories
sudo dnf config-manager setopt google-chrome.enabled=1
sudo dnf install google-chrome-stable
```

> Or grab the `.rpm` directly from <https://www.google.com/chrome/>.

## 5. GNOME Tweaks & Extensions

```bash
sudo dnf install gnome-tweaks gnome-extensions-app
```

Browse and toggle extensions at <https://extensions.gnome.org/> (install the browser connector first).

## 6. Zsh

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

## 7. Zsh plugins & Starship prompt

### Install plugins

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/zsh-syntax-highlighting
```

### Install Starship

```bash
curl -sS https://starship.rs/install.sh | sh
```

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

## 8. NVIDIA driver (optional)

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

**Enable RPM Fusion** (the driver lives here, not in Fedora's default repos):

```bash
sudo dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

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

## 9. Steam

Enable RPM Fusion (see [Part 2](#part-2--install-the-driver) above) if you haven't, then:

```bash
sudo dnf install steam
```

> GUI alternative: **Software → Enable third-party repositories → search "Steam"**.
