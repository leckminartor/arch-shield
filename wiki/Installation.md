# Installation

## Prerequisites

| Requirement | Required? | Notes |
|-------------|-----------|-------|
| Arch-based Linux (x86_64) | ✅ Required | Arch, CachyOS, EndeavourOS, Manjaro, Garuda, Artix |
| `bash` 4+ | ✅ Required | Pre-installed on all Arch systems |
| `sudo` or `doas` | ✅ Required | For system hooks and sysctl changes |
| `python3` | ⭕ Optional | For aur-malware-check integration |
| `git` | ⭕ Optional | For aur-malware-check download & threat-intel updates |
| AUR helper (`paru`, `yay`, `pikaur`, `trizen`) | ⭕ Recommended | For shell integration and build isolation |

The script auto-detects missing tools and warns you — it won't fail silently.

---

## Step 1: Download

```bash
curl -L -o arch-shield.sh https://github.com/leckminartor/arch-shield/raw/main/arch-shield.sh
```

**Verify integrity (recommended):**

Always inspect the script before running it with elevated privileges:

```bash
less arch-shield.sh
```

## Step 2: Make Executable

```bash
chmod +x arch-shield.sh
```

## Step 3: Dry Run (Recommended First Run)

Before making any changes, run a simulation to see what the script would do:

```bash
./arch-shield.sh --dry-run all
```

This shows all actions that *would* be taken without actually modifying your system.

## Step 4: Full Install

Once you're comfortable with the dry run output:

```bash
./arch-shield.sh all
```

This runs: Scan → Protect → Harden in sequence.

Alternatively, use the interactive menu:

```bash
./arch-shield.sh
```

## Step 5: Verify

Check that protection is active:

```bash
./arch-shield.sh status
```

---

## Uninstallation

To remove all arch-shield components:

1. Remove shell integration from your `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, or `~/.config/nushell/env.nu` — look for the arch-shield block and delete it
2. Remove pacman hooks:
   ```bash
   sudo rm /etc/pacman.d/hooks/aur-shield-pre-install.hook
   sudo rm /etc/pacman.d/hooks/aur-shield-post-install.hook
   ```
3. Remove systemd timer:
   ```bash
   sudo systemctl disable --now arch-shield.timer
   sudo rm /etc/systemd/system/arch-shield.{service,timer}
   ```
4. Remove aur-scanner and aur-malware-check (if installed by the script)
5. Revert sysctl changes (if applied during hardening)

---

## Troubleshooting Installation

### "Permission denied"
Make sure the script is executable: `chmod +x arch-shield.sh`

### "Command not found: paru/yay"
Install an AUR helper first, or run without shell integration (the script will skip it).

### "sudo: command not found"
Install `sudo` or `doas`. The script needs elevated privileges for system hooks and sysctl.

### Dry run shows errors
The dry run simulates all actions — some "errors" are expected (e.g., checking for files that don't exist yet). Only worry about errors in the actual run.