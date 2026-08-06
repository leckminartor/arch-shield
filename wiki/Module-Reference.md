# Module Reference

arch-shield consists of **7 modules**. Each can be run independently or combined via `./arch-shield.sh all`.

---

## 1. 🔍 System Scan

**Command:** `./arch-shield.sh scan`

Scans your system in 6 layers for AUR malware and compromise indicators.

### Scan Layers

| Layer | What it checks | How |
|-------|---------------|-----|
| **IOC Database** | 1,935+ known infected packages | Cross-references installed packages against community IOC feed |
| **PKGBUILD Analysis** | 87 static detection rules | Analyzes PKGBUILDs for malicious patterns (reverse shells, credential theft, eBPF rootkit, cryptominer, obfuscation) |
| **eBPF Rootkit** | Hidden BPF maps | Checks `/sys/fs/bpf/hidden_*` for rootkit traces |
| **npm/bun Cache** | Malicious npm packages | Scans for atomic-lockfile, js-digest, lockfile-js and similar |
| **systemd Persistence** | Suspicious services | Finds services with `Restart=always` and suspicious paths |
| **pacman Log** | Attack window installs | Reviews pacman log for installations during the attack period |

### Output Format

- 🟢 **Green** — No threats found
- 🟡 **Yellow** — Suspicious / needs review
- 🔴 **Red** — Infected / action required

---

## 2. 🛡️ Install Protection

**Command:** `./arch-shield.sh protect`

Installs automated protection layers that run continuously after setup.

### Components Installed

| Component | Description |
|-----------|-------------|
| **aur-scanner** | PKGBUILD security scanner with 87 detection rules |
| **aur-malware-check** | Community IOC database with 1,935+ infected packages |
| **Shell Integration** | Pre-scan before every `paru`/`yay` command (bash, zsh, fish, nu) |
| **Pacman Pre-Install Hook** | Blocks malware before installation (`AbortOnFail`) |
| **Pacman Post-Install Hook** | Scans after every installation |
| **systemd Timer** | Weekly automatic scan + threat-intel update (every Monday) |

### How Shell Integration Works

After installation, every time you run `paru -S <package>` or `yay -S <package>`, arch-shield automatically scans the package against the IOC database and PKGBUILD rules *before* the installation proceeds. If a threat is found, the command is aborted.

Supported shells: **bash**, **zsh**, **fish**, **nu (Nushell)**

---

## 3. 🔧 Harden System

**Command:** `./arch-shield.sh harden`

Applies kernel-level and configuration hardening to reduce attack surface.

### Hardening Measures

| Measure | What it does |
|---------|-------------|
| **eBPF Hardening** | Restricts eBPF loading via sysctl to prevent rootkit injection |
| **Build Isolation** | Enables paru chroot mode — AUR builds run in isolated environment |
| **Repo SigLevel** | Verifies pacman repository signature requirements |
| **AUR Helper Config** | Enables NewsOnUpgrade, UpgradeMenu, SaveChanges |
| **Firewall Status** | Checks if a firewall is active (nftables/ufw) |

---

## 4. 📊 Status

**Command:** `./arch-shield.sh status`

Shows a quick overview of all protection measures and their current state.

### What it shows:
- ✅/❌ aur-scanner installed
- ✅/❌ aur-malware-check installed
- ✅/❌ Shell integration active (per shell)
- ✅/❌ Pacman hooks installed
- ✅/❌ systemd timer active
- ✅/❌ eBPF hardening applied
- ✅/❌ Build isolation enabled
- ✅/❌ Last scan date & result
- ✅/❌ Threat-intel database age

---

## 5. 📦 Check Package

**Command:** `./arch-shield.sh check <package-name>`

Checks a single AUR package against all available databases without running a full system scan.

### Databases checked:
- IOC database (1,935+ known infected packages)
- PKGBUILD static analysis (if PKGBUILD is available)
- npm/bun cache entries (for npm packages)

### Example:
```bash
./arch-shield.sh check atomic-lockfile
# Output: 🔴 INFECTED — atomic-lockfile is in IOC database (credential stealer)
```

---

## 6. 🚨 Emergency Recovery

**Command:** `./arch-shield.sh emergency`

Guided 9-step recovery for confirmed infections. See [Emergency Recovery](Emergency-Recovery) for the full step-by-step guide.

> ⚠️ **Only run this if you have confirmed or strongly suspect an infection.** If an eBPF rootkit is detected, a full system reinstall is recommended.

---

## 7. 🔄 Threat-Intel Update

**Command:** `./arch-shield.sh update`

Updates all threat-intelligence databases to the latest versions.

### Sources:
| Source | Type | Update Method |
|--------|------|---------------|
| aur-malware-check | IOC database (1,935+ packages) | `git pull` |
| HedgeDoc | Community feed | HTTP fetch |
| Arch Linux News | Security advisories | RSS/API |

The weekly systemd timer runs this automatically every Monday. You can also run it manually at any time.

---

## Module Combinations

| Goal | Command |
|------|---------|
| Full setup (first time) | `./arch-shield.sh all` |
| Just scan, no changes | `./arch-shield.sh scan` |
| Update + scan | `./arch-shield.sh update && ./arch-shield.sh scan` |
| Check suspicious package | `./arch-shield.sh check <package>` |
| Preview everything | `./arch-shield.sh --dry-run all` |
| Emergency | `./arch-shield.sh emergency` |