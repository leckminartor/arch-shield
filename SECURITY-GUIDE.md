# 🔒 CachyOS / Arch Linux AUR Protection Plan
## Following the "Atomic Arch" Supply-Chain Attack (June 2026)

> **Date:** June 23, 2026  
> **System:** CachyOS (Arch Linux), Kernel 7.0.12-1-cachyos  
> **Status:** ✅ System is CLEAN — no infection found

---

## 📋 What Happened — The "Atomic Arch" Attack

### Summary

On **June 11, 2026**, a massive supply-chain attack on the **Arch User Repository (AUR)** was discovered. Attackers took over **1,500–2,000 orphaned AUR packages** and modified their `PKGBUILD` and `.install` files with malware.

### Attack Vectors

#### Wave 1: `atomic-lockfile` / `lockfile-js` (npm)
1. Attackers impersonated legitimate maintainers (e.g., `arojas`) via **Git commit spoofing**
2. Took over orphaned packages
3. Injected `npm install atomic-lockfile` or `npm install lockfile-js` into `.install` and `.hook` files
4. The npm packages contained a `preinstall` hook that executes `./src/hooks/deps`
5. `deps` is a **Rust-based credential stealer** (ELF binary)

#### Wave 2: `js-digest` (bun)
1. Additional attacker accounts (`custodiatovar`, `veramagalhaes`) took over orphaned packages
2. Injected `bun install js-digest` into PKGBUILD/`.install` files
3. Same npm publisher `herbsobering`
4. Embedded ELF payload with identical functionality

### Malware Capabilities

| Capability | Details |
|-----------|---------|
| **Credential Theft** | Discord tokens, GitHub PATs, npm tokens, Slack sessions, Teams/M365 sessions, SSH keys, Vault tokens, Docker/Podman credentials, browser cookies |
| **Data Exfiltration** | Uploads to `temp.sh`, C2 via Tor Onion Service |
| **Persistence** | systemd services (root or user mode) with `Restart=always` |
| **eBPF Rootkit** | When running as root with `CAP_BPF`: hides processes, files, and socket inodes |
| **Cryptominer** | References to `/usr/bin/monero-wallet-gui` |

### Known Attacker Accounts
- `krisztinavarga`, `franziskaweber`, `tobiaswesterburg`, `ellenmyklebust`
- `custodiatovar`, `veramagalhaes`
- `ivonahruskova` (account created June 11, 16 adoptions)
- `simongeisler` (3 days old, 16 adoptions)

### Previous Incidents
- **July 2018:** `xeactor` takes over `acroread` (PDF Viewer) with malware
- **July 2025:** Fake browser packages with Remote Access Trojan (CHAOS RAT)
- **August 2025:** Week-long DDoS attack on Arch Linux

---

## ✅ Immediate Actions — Already Completed

### 1. System Scan: CLEAN ✅
- **aur-malware-check** (community tool, 1,935 known infected packages): CLEAN
- **aur-scan system** (87 detection rules): Only 1 false positive (google-chrome cron job with explanatory `rm -r` command)
- **eBPF Rootkit Check:** No hidden maps
- **npm/bun Cache Check:** No malware packages
- **systemd Persistence Check:** No suspicious services
- **pacman.log History:** No infected installations

### 2. Fish Shell Integration Enabled ✅
- `source /usr/share/aur-scan/integration.fish` added to `~/.config/fish/config.fish`
- Automatically scans before every `paru -S` / `paru -Syu` command
- Interactive mode: prompts before installation when threats are found

### 3. User IOC Database Created ✅
- `~/.local/share/aur-scanner/ioc.toml` with Atomic-Arch and CHAOS-RAT campaigns

### 4. Weekly systemd Scan Timer Enabled ✅
- Service: `aur-scan-weekly.service` (user-level)
- Timer: `aur-scan-weekly.timer` — runs every Monday
- Executes `aur-scan system`, `aur-malware-check`, eBPF check, npm/bun cache check
- Log: `~/.local/share/aur-scanner/scan-log.txt`

### 5. Secure paru.conf Created ✅
- `NewsOnUpgrade`: Shows Arch news before every upgrade
- `CombinedUpgrade`: Repo + AUR together
- `UpgradeMenu`: Packages can be deselected
- `SaveChanges`: PKGBUILD changes are saved
- `RemoveMake` / `CleanAfter`: Build environment is cleaned up

---

## ⚠️ Manual Actions Required (needs sudo)

### 6. Install Pre-Install pacman Hook
```bash
sudo cp /tmp/aur-scan-pre-install.hook /etc/pacman.d/hooks/aur-scan-pre-install.hook
```

### 7. Enable eBPF Hardening (CRITICAL — Rootkit Protection)
```bash
sudo cp /tmp/99-arch-shield-ebpf.conf /etc/sysctl.d/99-arch-shield-ebpf.conf
sudo sysctl -p /etc/sysctl.d/99-arch-shield-ebpf.conf
```

### 8. Secure CachyOS Repo (CRITICAL — Supply-Chain Protection)
```bash
sudo sed -i 's/SigLevel = Optional TrustAll/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
```

### 9. Enable Build Isolation (CRITICAL — Prevents Credential Theft)
```bash
sudo pacman -S devtools
echo 'Chroot' >> ~/.config/paru/paru.conf
```

### (Optional) Extend sudo Timeout for paru
```bash
# In /etc/sudoers.d/10-paru:
# Defaults!/usr/bin/makepkg timestamp_timeout=30
```

---

## 🛡️ Long-Term Protection Strategy

### A. General AUR Rules

1. **ALWAYS review the PKGBUILD** — Read every `PKGBUILD` and every `.install` file before installation
   ```bash
   paru -Si <package>          # Show info
   paru -Gp <package>          # Show PKGBUILD
   ```

2. **Check the maintainer** — Click the maintainer name on the AUR page.
   - How old is the account?
   - How many packages do they maintain?
   - ⚠️ Newly created accounts with many adoptions = Red Flag

3. **Avoid orphaned packages** — `Flagged out-of-date` or `Maintainer: orphan` are risky

4. **Check commits** — Look at recent commits on the AUR page under "View Changes"

5. **Check popularity** — Packages with 0-1 votes that were recently adopted are suspicious

### B. npm/Node-Specific

The Atomic-Arch malware was loaded via npm `preinstall` hooks:
- ⚠️ **NEVER** run `npm install` or `bun install` in a PKGBUILD without thorough understanding
- Watch for these patterns:
  ```
  npm install atomic-lockfile     # MALWARE
  npm install lockfile-js         # MALWARE
  bun install js-digest           # MALWARE
  npm install <unknown-package>   # SUSPICIOUS
  ```

### C. System Hardening

1. **Keep pacman SigLevel strict:**
   ```ini
   SigLevel = Required DatabaseOptional
   ```
   The `[cachyos]` repo currently uses `SigLevel = Optional TrustAll` — this is intended by the CachyOS team, but you can set it to `Required` if desired.

2. **Restrict eBPF module (if possible):**
   ```bash
   # In /etc/sysctl.d/99-ebpf-hardening.conf:
   kernel.unprivileged_bpf_disabled = 1
   ```
   This prevents non-root users from loading eBPF programs (rootkit protection)

3. **Kernel lockdown (for maximum security):**
   ```bash
   # Kernel parameter: lockdown=confidentiality
   ```

### D. Regular Auditing

1. **Weekly scan** — Runs automatically via systemd timer ✅
2. **Subscribe to Arch news** — https://archlinux.org/news/ RSS feed
3. **Monitor aur-general mailing list** — https://lists.archlinux.org/
4. **aur-malware-check repository** — Update regularly:
   ```bash
   cd /tmp/aur-malware-check && git pull
   ```

### E. Emergency Plan (if infected)

1. **Do NOT shut down the system** — First capture forensic evidence with trusted media
2. **Rotate ALL credentials:**
   - Discord, GitHub, npm, Slack, Teams, SSH keys
   - Vault tokens, cloud provider keys, browser cookies
3. **Check persistence:**
   ```bash
   systemctl list-units --type=service --state=running
   ls -la /sys/fs/bpf/hidden_*
   ```
4. **Clean with trusted media** — Boot Arch ISO, mount filesystem, remove malicious systemd units
5. **Consider reinstalling** — eBPF rootkit makes the system untrustworthy

---

## 🔧 Installed Protection Measures — Overview

| Component | Status | Location |
|-----------|--------|----------|
| **aur-scanner** (v2.0.0) | ✅ Installed | `/usr/bin/aur-scan` |
| **aur-malware-check** (v4.0) | ✅ Installed | `/tmp/aur-malware-check/` |
| **Fish Shell Integration** | ✅ Enabled | `~/.config/fish/config.fish` |
| **Pre-Install pacman Hook** | ⚠️ Manual required | `/etc/pacman.d/hooks/aur-scan-pre-install.hook` |
| **Post-Install pacman Hook** | ✅ Already active | `/etc/pacman.d/hooks/aur-shield-after-install.hook` |
| **Weekly systemd Timer** | ✅ Enabled | `~/.config/systemd/user/aur-scan-weekly.timer` |
| **IOC Database** | ✅ Created | `~/.local/share/aur-scanner/ioc.toml` |
| **Secure paru.conf** | ✅ Active | `~/.config/paru/paru.conf` |
| **Scan Log** | ✅ Maintained | `~/.local/share/aur-scanner/scan-log.txt` |

---

## 📚 Sources

- [Arch Linux Official Advisory](https://archlinux.org/news/active-aur-malicious-packages-incident/)
- [BleepingComputer Report](https://www.bleepingcomputer.com/news/security/over-400-arch-linux-packages-compromised-to-push-rootkit-infostealer/)
- [Truesec Analysis](https://www.truesec.com/hub/blog/supply-chain-attack-compromising-arch-linux-aur-packages-infostealer-rootkit)
- [CloudSecurityAlliance eBPF Rootkit Analysis](https://labs.cloudsecurityalliance.org/research/csa-research-note-aur-supply-chain-ebpf-rootkit-20260614-csa/)
- [aur-malware-check Detection Tool](https://github.com/lenucksi/aur-malware-check)
- [Sonatype Atomic Arch Analysis](https://www.sonatype.com/blog/atomic-arch-npm-campaign-adds-malicious-dependency)
- [The Hacker News](https://thehackernews.com/2026/06/over-400-arch-linux-aur-packages.html)
- [StepSecurity Analysis](https://www.stepsecurity.io/blog/400-aur-packages-hijacked-atomic-arch-campaign)
- [FOSSForce: Arch Says All's Clear](https://fossforce.com/2026/06/arch-says-alls-clear-after-aur-malware-incident-affects-1500-packages/)
- [CachyOS Forum Thread](https://discuss.cachyos.org/t/aur-compromised-almost-2000-packages-affected-20260611/31040)
- [CachyOS Forum: How to Check](https://discuss.cachyos.org/t/how-to-check-for-compromised-packages-from-the-current-aur-malware-attack/31077)

---

## 📝 Security Notice

> ⚠️ **The AUR is an unofficial, user-produced, unvetted repository.**
> The only safe way to use the AUR is to **review every single line** in `PKGBUILD` and `.install` files before installation.
> — Arch Linux Team, June 2026