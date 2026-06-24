# Commands & Usage

## Command Overview

| Command | Description | Needs sudo? |
|--------|-------------|-------------|
| `./arch-shield.sh` | Interactive menu | Depends on selection |
| `./arch-shield.sh scan` | Scan system for malware | Recommended |
| `./arch-shield.sh protect` | Install all protection measures | ✅ Yes |
| `./arch-shield.sh harden` | Kernel, build isolation & repo hardening | ✅ Yes |
| `./arch-shield.sh status` | Show protection status | No |
| `./arch-shield.sh check <package>` | Check a specific AUR package | No |
| `./arch-shield.sh all` | Everything: Scan + Protect + Harden | ✅ Yes |
| `./arch-shield.sh emergency` | Emergency recovery (confirmed infection) | ✅ Yes |
| `./arch-shield.sh update` | Update threat-intelligence databases | No |
| `./arch-shield.sh --dry-run <cmd>` | Simulation (nothing changes) | No |
| `./arch-shield.sh help` | Show help | No |

---

## Detailed Command Reference

### Interactive Menu

```bash
./arch-shield.sh
```

Shows a numbered menu with all 7 modules. Pick a number to run that module. Best for first-time users.

### scan

```bash
./arch-shield.sh scan
```

Runs the 6-layer system scan. Checks for:
- 1,935+ known infected packages (IOC database)
- 118 PKGBUILD detection rules (static analysis)
- eBPF rootkit traces
- npm/bun cache malicious packages
- systemd persistence mechanisms
- pacman log history (installations during attack window)

Output is color-coded: 🟢 clean, 🟡 suspicious, 🔴 infected.

### protect

```bash
./arch-shield.sh protect
```

Installs all protection components:
- aur-scanner (PKGBUILD security scanner)
- aur-malware-check (IOC database)
- Shell integration (bash, zsh, fish, nu)
- Pacman pre-install hook (blocks malware)
- Pacman post-install hook (scans after install)
- Weekly systemd timer (auto scan + update every Monday)

### harden

```bash
./arch-shield.sh harden
```

Applies system hardening:
- eBPF hardening via sysctl
- Build isolation (paru chroot mode)
- Repo SigLevel verification
- AUR helper configuration (NewsOnUpgrade, UpgradeMenu, SaveChanges)
- Firewall status check

### status

```bash
./arch-shield.sh status
```

Shows an overview of all installed protection measures and their current state. Quick way to verify everything is working.

### check

```bash
./arch-shield.sh check <package-name>
```

Checks a single AUR package against all databases:
- IOC database (known infected packages)
- PKGBUILD static analysis (if PKGBUILD is available)

Example:
```bash
./arch-shield.sh check atomic-lockfile
```

### all

```bash
./arch-shield.sh all
```

Runs everything in sequence: Scan → Protect → Harden. This is the recommended one-command setup for new installations.

### emergency

```bash
./arch-shield.sh emergency
```

Launches the guided 9-step emergency recovery. See [Emergency Recovery](Emergency-Recovery) for details.

**Only run this if you have confirmed or strongly suspect an infection.**

### update

```bash
./arch-shield.sh update
```

Updates all threat-intelligence databases:
- aur-malware-check IOC database (git pull)
- HedgeDoc community feeds
- Arch Linux security news

Recommended to run regularly, or let the systemd timer handle it automatically.

### --dry-run

```bash
./arch-shield.sh --dry-run <command>
```

Simulates any command without making changes. Useful for:
- Previewing what `all` would do
- Checking if `protect` would install hooks correctly
- Testing `harden` before applying sysctl changes

Example:
```bash
./arch-shield.sh --dry-run all
./arch-shield.sh --dry-run protect
./arch-shield.sh --dry-run harden
```

### help

```bash
./arch-shield.sh help
```

Shows all available commands and a brief description.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success / no threats found |
| 1 | Threats detected (scan) |
| 2 | Missing dependencies |
| 3 | Permission error (sudo required) |
| 4 | Configuration error |
| 5 | Emergency recovery incomplete |

---

## Tips

- **Always dry-run first** on new systems: `./arch-shield.sh --dry-run all`
- **Run `update` before `scan`** to ensure you have the latest IOC database
- **Check `status` after `protect`** to verify all components are active
- **Use `check` before installing** a suspicious AUR package: `./arch-shield.sh check <pkg>`
- The **systemd timer** runs `scan` + `update` automatically every Monday — no need to manual scan unless you install packages frequently