# Configuration

This page covers all configuration options that arch-shield applies and how to customize them.

---

## AUR Helper Configuration

When you run `./arch-shield.sh harden`, arch-shield applies secure defaults to your AUR helper config.

### paru

File: `~/.config/paru/paru.conf`

| Setting | Value | Why |
|---------|-------|-----|
| `NewsOnUpgrade` | Yes | Shows Arch news before upgrading — you'll see security advisories |
| `UpgradeMenu` | Yes | Shows a review menu before installing — chance to abort |
| `SaveChanges` | Yes | Saves PKGBUILD changes for review |
| `UseReview` | Yes | Opens PKGBUILD in editor before building |
| `Chroot` | Yes | Builds in isolated chroot — prevents build-time malware from touching your system |
| `CleanAfter` | Yes | Removes build files after installation |
| `DiffMenu` | Yes | Shows diff of PKGBUILD changes on update |

### yay

File: `~/.config/yay/config.json`

| Setting | Value | Why |
|---------|-------|-----|
| `news_on_upgrade` | true | Shows Arch news before upgrading |
| `clean_after` | true | Removes build files after installation |
| `diff_menu` | true | Shows PKGBUILD diff on update |
| `review` | true | Opens PKGBUILD for review before building |

---

## Shell Integration

arch-shield installs a pre-scan hook into your shell configuration. When you run `paru -S <pkg>` or `yay -S <pkg>`, the package is scanned before installation proceeds.

### Supported Shells

| Shell | Config File | Integration Method |
|-------|-------------|---------------------|
| **bash** | `~/.bashrc` | Function wrapper around `paru`/`yay` |
| **zsh** | `~/.zshrc` | Function wrapper |
| **fish** | `~/.config/fish/config.fish` | Function definition |
| **nu (Nushell)** | `~/.config/nushell/env.nu` | Custom command |

### What the integration does

1. Intercepts `paru -S` / `paru -Syu` / `yay -S` / `yay -Syu` commands
2. Downloads the PKGBUILD for each package
3. Runs the PKGBUILD through the 87-rule static scanner
4. Checks package name against IOC database
5. If threats found:
   - 🔴 Critical → **Aborts** the command
   - 🟡 Warning → Asks for confirmation
   - 🟢 Clean → Proceeds normally

### Disabling Shell Integration

To temporarily disable for a single command:
```bash
# Bypass shell integration (USE WITH CAUTION)
command paru -S <package>
```

To permanently remove:
```bash
./arch-shield.sh status  # Check which shells have integration
# Manually remove the arch-shield block from your shell config file
```

---

## Pacman Hooks

### Pre-Install Hook

File: `/etc/pacman.d/hooks/aur-shield-pre-install.hook`

**Trigger:** `PreTransaction` — runs before any package installation

**What it does:**
1. Gets list of packages about to be installed
2. Checks each against IOC database
3. If any match → **aborts entire transaction** (`AbortOnFail`)
4. You see: `error: failed to commit transaction (hook failed)`

**Override (not recommended):**
```bash
sudo pacman -S <package> --overwrite '*'  # Still triggers hook
# To truly bypass, you'd need to remove the hook file
```

### Post-Install Hook

File: `/etc/pacman.d/hooks/aur-shield-post-install.hook`

**Trigger:** `PostTransaction` — runs after package installation

**What it does:**
1. Gets list of just-installed packages
2. Runs full scan on each
3. Logs results to `journalctl`
4. If threats found → logs warning (does NOT auto-remove)

---

## systemd Timer

### Timer Configuration

File: `/etc/systemd/system/arch-shield.timer`

| Property | Default | Description |
|----------|---------|-------------|
| `OnCalendar` | `Mon *-*-* 09:00:00` | Every Monday at 9:00 AM |
| `Persistent` | `yes` | Runs missed execution after boot |
| `Unit` | `arch-shield.service` | The service to trigger |

### Service Configuration

File: `/etc/systemd/system/arch-shield.service`

| Property | Value |
|----------|-------|
| `Type` | `oneshot` |
| `ExecStart` | `arch-shield.sh update && arch-shield.sh scan` |
| `Nice` | 10 (low priority — doesn't slow your system) |

### Customizing the Schedule

To change the weekly scan to daily:
```bash
sudo systemctl edit arch-shield.timer
```

In the editor, add:
```ini
[Timer]
OnCalendar=*-*-* 09:00:00
```

Save and reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart arch-shield.timer
```

---

## eBPF Hardening (sysctl)

When you run `./arch-shield.sh harden`, the following sysctl values are applied:

| sysctl Key | Value | Effect |
|------------|-------|--------|
| `kernel.unprivileged_bpf_disabled` | `2` | Only root can load BPF programs (prevents unprivileged eBPF rootkit injection) |
| `net.core.bpf_jit_harden` | `2` | Hardens BPF JIT compiler against attacks |
| `kernel.kptr_restrict` | `2` | Hides kernel pointers from unprivileged users |

### Reverting sysctl changes

```bash
sudo sysctl -w kernel.unprivileged_bpf_disabled=0
sudo sysctl -w net.core.bpf_jit_harden=0
sudo sysctl -w kernel.kptr_restrict=1
```

> ⚠️ Reverting these settings reduces your security. Only do this if a specific application requires it.

---

## Dry Run Mode

All commands support `--dry-run`:

```bash
./arch-shield.sh --dry-run all
./arch-shield.sh --dry-run protect
./arch-shield.sh --dry-run harden
./arch-shield.sh --dry-run scan
```

In dry run mode, the script:
- Shows all actions that *would* be taken
- Does NOT modify any files
- Does NOT install any packages
- Does NOT apply sysctl changes
- Does NOT create hooks or timers

**Always use dry-run first on new systems.**