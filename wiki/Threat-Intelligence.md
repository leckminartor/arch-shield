# Threat Intelligence

arch-shield uses multiple threat-intelligence feeds to detect known AUR malware. This page explains each source and how they're updated.

---

## IOC Databases

### aur-malware-check

- **Repository:** [lenucksi/aur-malware-check](https://github.com/lenucksi/aur-malware-check)
- **Type:** Community-maintained IOC (Indicator of Compromise) database
- **Contents:** 1,935+ known infected AUR package names
- **Update method:** `git pull` (when installed) or manual download
- **Used by:** System Scan (Layer 1), Package Check, Pacman Pre-Install Hook

This is the primary database for detecting known-bad packages. When the systemd timer runs the weekly update, it pulls the latest version of this database.

### aur-scanner (leckminartor fork)

- **Repository:** [leckminartor/ks-aur-scanner](https://github.com/leckminartor/ks-aur-scanner)
- **Type:** PKGBUILD static analysis engine
- **Contents:** 87 detection rules for malicious patterns in PKGBUILDs
- **Used by:** System Scan (Layer 2), Package Check, Shell Integration

This scanner performs static analysis on PKGBUILDs — it doesn't need a database of known-bad packages, it detects *patterns* that indicate malicious intent.

---

## Community Feeds

### HedgeDoc Feed

- **Type:** Community-curated threat intelligence
- **Content:** Newly discovered malicious packages, updated IOC lists
- **Update method:** HTTP fetch during `./arch-shield.sh update`
- **Frequency:** Updated by community members as new threats are discovered

### Arch Linux Security News

- **Source:** [archlinux.org/news](https://archlinux.org/news/)
- **Type:** Official Arch Linux security advisories
- **Content:** Official announcements about compromised packages, vulnerabilities
- **Update method:** RSS/API fetch during `./arch-shield.sh update`
- **Frequency:** Published by Arch Linux team as needed

---

## Update Mechanism

### Manual Update

```bash
./arch-shield.sh update
```

Updates all databases:
1. `git pull` in aur-malware-check directory (if installed)
2. Fetch HedgeDoc community feed
3. Fetch Arch Linux news
4. Rebuild internal cache

### Automatic Update (systemd Timer)

When `./arch-shield.sh protect` is run, it installs a systemd timer:

| Property | Value |
|----------|-------|
| Timer name | `arch-shield.timer` |
| Schedule | Every Monday at 09:00 |
| Action | `arch-shield.service` → runs `arch-shield.sh update && arch-shield.sh scan` |
| Persistent | Yes (catches up after sleep/shutdown) |

Check timer status:
```bash
systemctl list-timers arch-shield.timer
```

View timer log:
```bash
journalctl -u arch-shield.service
```

---

## Adding Custom IOC Sources

You can contribute new IOC sources:

1. Open an [Issue](https://github.com/leckminartor/arch-shield/issues) with the source URL and format
2. Or submit a PR that adds the source to the update module

**Requirements for IOC sources:**
- Must be publicly accessible (no auth required)
- Must list package names (one per line or JSON array)
- Must be actively maintained
- Must include a description of how packages were identified as malicious

---

## Database freshness

Check when databases were last updated:

```bash
./arch-shield.sh status
```

The status output shows:
- aur-malware-check last update date
- aur-scanner version
- Last weekly scan result
- Database age warning (if > 7 days old)

> 💡 **Tip:** If you install AUR packages frequently, consider running `./arch-shield.sh update` manually before each install session, rather than waiting for the weekly timer.