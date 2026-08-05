# 🛡️ arch-shield

**Arch Linux AUR Security Hardening Script** — Protects any Arch-based system against AUR malware.

> Response to the [Atomic-Arch Supply-Chain Attack (June 2026)](https://archlinux.org/news/active-aur-malicious-packages-incident/), where 1,500+ AUR packages were compromised with credential stealers and eBPF rootkits.

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-supported-blue.svg)](https://archlinux.org)
[![Version](https://img.shields.io/badge/version-1.5.0-green.svg)](https://github.com/leckminartor/arch-shield/releases)

**[Deutsch](README.de.md)** | **English**

---

## Compatible Distributions

Arch Linux · CachyOS · EndeavourOS · Manjaro · Garuda Linux · Artix Linux · and all Arch-based distributions

## Quick Start

```bash
# Download
curl -L -o arch-shield.sh https://github.com/leckminartor/arch-shield/raw/main/arch-shield.sh

# Make executable
chmod +x arch-shield.sh

# Interactive menu
./arch-shield.sh

# Or directly: Everything (Scan + Protect + Harden)
./arch-shield.sh all

# Dry run first (nothing will be changed)
./arch-shield.sh --dry-run all
```

## Commands

| Command | Description |
|--------|-------------|
| `./arch-shield.sh` | Interactive menu |
| `./arch-shield.sh scan` | Scan system for malware |
| `./arch-shield.sh protect` | Install all protection measures |
| `./arch-shield.sh harden` | Kernel, build isolation & repo hardening |
| `./arch-shield.sh status` | Show protection status |
| `./arch-shield.sh check <package>` | Check a specific AUR package |
| `./arch-shield.sh all` | Everything: Scan + Protect + Harden |
| `./arch-shield.sh emergency` | **Emergency recovery for confirmed infection** |
| `./arch-shield.sh update` | **Update threat-intelligence databases** |
| `./arch-shield.sh --dry-run <cmd>` | Simulation (nothing will be changed) |
| `./arch-shield.sh help` | Show help |

## Modules

The script has **7 modules**:

1. **🔍 System Scan** — 6-layer scan: 1,935 IOC packages, static PKGBUILD analysis (118 rules), eBPF rootkit, npm/bun cache, systemd persistence, pacman log history
2. **🛡️ Install Protection** — aur-scanner, aur-malware-check, shell integration, pre/post-install hooks, weekly systemd timer
3. **🔧 Harden System** — eBPF hardening, build isolation (chroot), repo SigLevel verification, AUR helper configuration, firewall status
4. **📊 Status** — Overview of all installed protection measures
5. **📦 Check Package** — Check individual AUR package against all databases
6. **🚨 Emergency Recovery** — Guided 9-step recovery for confirmed infections (snapshot, credential rotation, cleanup, verification)
7. **🔄 Threat-Intel Update** — Updates IOC databases from community feeds (git pull, HedgeDoc, Arch News)

## What Gets Installed

- **aur-scanner** — PKGBUILD security scanner with 118 detection rules
- **aur-malware-check** — Community IOC database with 1,935+ infected packages
- **Shell Integration** — Scans before every `paru`/`yay` command (bash, zsh, fish, nu)
- **Pacman Pre-Install Hook** — Blocks malware before installation (`AbortOnFail`)
- **Pacman Post-Install Hook** — Scans after every installation
- **Weekly systemd Timer** — Automatic scan + threat-intel update every Monday
- **eBPF Hardening** — Rootkit protection via sysctl
- **Build Isolation** — paru chroot mode for isolated AUR builds
- **Secure AUR Helper Configuration** — NewsOnUpgrade, UpgradeMenu, SaveChanges

## What the Scan Checks

1. **1,935+ known infected packages** — Cross-referenced with community IOC database
2. **Static PKGBUILD analysis** — 118 detection rules (Reverse Shells, Credential Theft, eBPF Rootkit, Cryptominer, Obfuscation, ...)
3. **eBPF rootkit traces** — `/sys/fs/bpf/hidden_*` maps
4. **npm/bun cache** — Malicious packages (atomic-lockfile, js-digest, lockfile-js)
5. **systemd persistence** — Suspicious services with `Restart=always`
6. **pacman log history** — Installations during the attack window

## Emergency Recovery

If infection is confirmed, `./arch-shield.sh emergency` guides you through 9 steps:

1. Document system status (forensic snapshot)
2. Rotate credentials (GitHub, npm, SSH, browsers, ...)
3. Remove infected packages
4. Remove persistence (systemd, cron, autostart, bashrc)
5. Remove eBPF rootkit (→ reinstall recommended)
6. Remove suspicious files in /tmp, /dev/shm
7. Clean AUR build cache and npm/bun cache
8. Reload systemd
9. Verification scan — is the system really clean?

> ⚠️ If an eBPF rootkit is detected, reinstalling the system is recommended — the rootkit can hide processes and files.

## Requirements

- Arch-based Linux (x86_64)
- `bash` 4+
- `python3` (for aur-malware-check, optional)
- `git` (for aur-malware-check download, optional)
- `sudo` or `doas` (for system hooks and sysctl)
- An AUR helper (`paru`, `yay`, `pikaur`, `trizen`) — recommended

The script auto-detects: distribution, AUR helper, shell, sudo availability, and missing tools.

## Code Review

This script was code-reviewed by two AI models:
- **qwen3-coder:480b** — Bash/Security Code Review (syntax, quoting, race conditions, robustness)
- **deepseek-v4-pro** — Security Architecture Review (attack vectors, build isolation, repo security)

It was tested in a Distrobox Arch container environment (scan, emergency recovery with simulated malware).

## Sources

- [Arch Linux Advisory](https://archlinux.org/news/active-aur-malicious-packages-incident/)
- [aur-malware-check](https://github.com/lenucksi/aur-malware-check)
- [aur-scanner](https://github.com/KiefStudioMA/ks-aur-scanner)
- [BleepingComputer Report](https://www.bleepingcomputer.com/news/security/over-400-arch-linux-packages-compromised-to-push-rootkit-infostealer/)
- [Truesec Analysis](https://www.truesec.com/hub/blog/supply-chain-attack-compromising-arch-linux-aur-packages-infostealer-rootkit)
- [CloudSecurityAlliance eBPF Rootkit Analysis](https://labs.cloudsecurityalliance.org/research/csa-research-note-aur-supply-chain-ebpf-rootkit-20260614-csa/)

## Disclaimer

This project is provided voluntarily and without warranty.

**NO LIABILITY** is assumed — neither for direct nor indirect damages, data loss, system failures, or security incidents resulting from the use of this script.

- ❌ **No guarantee** of 100% protection against all threats
- ❌ **No guarantee** of error-free operation in every environment
- ❌ **No liability** for false detections (False Positives) or missed threats (False Negatives)
- ❌ **No liability** for damage to system, data, or credentials

**Use at your own risk.**

This script is a supplement to — not a replacement for — your own diligence, manual PKGBUILD reviews, and established security practices. The AUR is an unofficial, community-maintained repository. The only safe usage requires reviewing every line in `PKGBUILD` and `.install` files before installation.

## Donate

If this script helped you, I appreciate a donation:

[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://paypal.me/klausminator)

## License

GPL-3.0-or-later — see [LICENSE](LICENSE)