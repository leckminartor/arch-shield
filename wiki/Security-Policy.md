# Security Policy

## Reporting a Vulnerability

If you discover a vulnerability in arch-shield, please report it responsibly.

### How to Report

**Preferred:** Use GitHub's private vulnerability reporting:
1. Go to [github.com/leckminartor/arch-shield](https://github.com/leckminartor/arch-shield)
2. Click **"Security"** tab → **"Report a vulnerability"**
3. Describe the vulnerability with:
   - Affected version
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

**Alternative:** Open a private Issue (mark as `security` label — maintainers will handle it confidentially).

### Response Timeline

| Step | Expected Time |
|------|---------------|
| Acknowledgment | Within 48 hours |
| Initial assessment | Within 7 days |
| Fix or mitigation | Within 30 days (severity dependent) |
| Public disclosure | After fix is released, coordinated with reporter |

---

## What to Report

### Security issues in arch-shield itself

- Command injection in the script
- Privilege escalation via the script
- Bypass of detection rules
- Hook bypass (malware that evades the pre-install hook)
- Shell integration bypass
- Issues in the IOC update mechanism

### NOT security issues

- Malware that arch-shield doesn't detect (this is a detection gap, not a vulnerability — report as a feature request/Issue)
- False positives (report as an Issue, not a security vulnerability)
- General Arch Linux security issues (report to Arch Linux, not here)

---

## Security Architecture

### Trust Model

| Component | Trusted? | Notes |
|-----------|----------|-------|
| arch-shield.sh | ✅ | Reviewed code, runs locally |
| aur-malware-check (IOC DB) | ⚠️ | Community-maintained — trust the community, but verify |
| aur-scanner (rules) | ⚠️ | Community-maintained detection rules |
| HedgeDoc feeds | ⚠️ | Community-curated — verify sources |
| Arch Linux News | ✅ | Official Arch Linux project |
| pacman hooks | ✅ | Installed locally, no network calls |
| systemd timer | ✅ | Runs locally, no network calls except update |

### What arch-shield does NOT do

- Does NOT send data anywhere (no telemetry, no phone-home)
- Does NOT execute downloaded code automatically
- Does NOT modify the kernel directly
- Does NOT install a background daemon (uses systemd timer, which runs on schedule)
- Does NOT require network access for scanning (only for updates)

### Permissions Used

| Permission | Why | When |
|------------|-----|------|
| `sudo` (root) | Install pacman hooks, systemd timer, apply sysctl | `protect`, `harden`, `emergency` |
| Read filesystem | Scan installed packages, logs, caches | `scan`, `check` |
| Network | Update IOC databases, fetch Arch news | `update` (only) |
| Write `~/.bashrc` etc. | Install shell integration | `protect` |
| Write `/etc/pacman.d/hooks/` | Install pacman hooks | `protect` |
| Write `/etc/systemd/system/` | Install systemd timer | `protect` |

---

## Best Practices for Users

1. **Always review the script before running** — `less arch-shield.sh`
2. **Run `--dry-run` first** — see what would change
3. **Keep IOC databases updated** — `./arch-shield.sh update` or rely on weekly timer
4. **Don't bypass hooks without reason** — the pre-install hook is your last line of defense
5. **Report false positives** — helps improve detection accuracy for everyone
6. **Review PKGBUILDs manually** — arch-shield is a supplement, not a replacement for manual review