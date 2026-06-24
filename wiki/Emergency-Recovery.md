# Emergency Recovery

The `./arch-shield.sh emergency` module guides you through a 9-step recovery process if your system has been compromised by AUR malware.

> ⚠️ **WARNING:** Only run this if you have confirmed or strongly suspect an infection. If an eBPF rootkit is detected, a **full system reinstall is recommended** — the rootkit can hide processes and files, making recovery unreliable.

---

## When to Use Emergency Recovery

Run `./arch-shield.sh emergency` if:
- `./arch-shield.sh scan` detected infected packages (🔴)
- You installed packages from the AUR during the attack window (June 2026)
- You notice suspicious network activity, unknown systemd services, or missing credentials
- Your AUR helper warned you about a malicious package after installation

---

## The 9 Steps

### Step 1: Document System Status (Forensic Snapshot)

Before changing anything, the script captures the current system state:

- List of all installed packages (`pacman -Q`)
- Running processes (`ps aux`)
- Network connections (`ss -tulpn`)
- systemd services (`systemctl list-units --type=service`)
- Crontab entries (`crontab -l`)
- BPF maps and programs (`bpftool` if available)
- pacman log tail

This snapshot is saved to a timestamped file for later analysis.

### Step 2: Rotate Credentials

If credentials were stolen, rotating them immediately is critical. The script guides you through rotating:

| Credential Type | Action |
|----------------|--------|
| **GitHub** | Revoke all tokens, generate new SSH key, update `git config` |
| **npm** | `npm token revoke` all tokens, create new `.npmrc` |
| **SSH keys** | Remove `~/.ssh/known_hosts` entries, generate new keys |
| **Browser** | Clear saved passwords, log out of all sessions |
| **API keys** | Check environment variables, rotate any exposed keys |
| **GPG keys** | Check if private keys were accessed, revoke if necessary |
| **Docker** | Check `~/.docker/config.json`, rotate registry credentials |
| **Cloud** | Check `~/.aws/credentials`, `~/.config/gcloud/`, etc. |

> The script **does not** rotate credentials automatically — it guides you through each step and pauses for confirmation.

### Step 3: Remove Infected Packages

- Cross-references installed packages against the IOC database
- Lists all infected packages found
- Asks for confirmation before removing each package
- Uses `pacman -Rns` for complete removal (including dependencies and config)

### Step 4: Remove Persistence

Malware commonly establishes persistence through multiple mechanisms. The script checks and cleans:

| Mechanism | Where it looks | Action |
|-----------|---------------|--------|
| **systemd services** | `/etc/systemd/system/`, `~/.config/systemd/` | Removes suspicious `.service` files with `Restart=always` |
| **cron jobs** | `/etc/cron.d/`, `/etc/crontab`, `crontab -l` | Removes suspicious entries |
| **autostart** | `~/.config/autostart/`, `/etc/xdg/autostart/` | Removes suspicious `.desktop` files |
| **Shell rc** | `~/.bashrc`, `~/.zshrc`, `~/.profile` | Removes injected malicious lines |
| **ld.so.preload** | `/etc/ld.so.preload` | Removes if present (should not exist normally) |
| **XDG portals** | `~/.config/autostart/` | Checks for hidden autostart entries |

### Step 5: Remove eBPF Rootkit

If eBPF rootkit traces were detected in Step 1:

- Unloads suspicious BPF programs (`bpftool prog show` → unload)
- Removes hidden BPF maps from `/sys/fs/bpf/`
- Resets `unprivileged_bpf_disabled` sysctl

> ⚠️ **IMPORTANT:** If an eBPF rootkit was active, the script will display a prominent warning recommending a **full system reinstall**. eBPF rootkits can hide processes, files, and network connections — you cannot fully trust a system that had an active eBPF rootkit, even after cleanup.

### Step 6: Clean Suspicious Temp Files

Scans and cleans:
- `/tmp/` — suspicious executables, scripts, BPF objects
- `/dev/shm/` — shared memory abuse (common for keyloggers)
- `/var/tmp/` — persistent temp storage
- `~/.cache/` — application cache that may contain malware payloads

### Step 7: Clean Build Caches

| Cache | Action |
|-------|--------|
| **AUR build cache** | `paru -Scc` or `yay -Scc` (clears `~/.cache/paru/` or `~/.cache/yay/`) |
| **npm cache** | `npm cache clean --force` |
| **bun cache** | `rm -rf ~/.bun/install/cache` |
| **pip cache** | `pip cache purge` |
| **go cache** | `go clean -cache` |

### Step 8: Reload systemd

```bash
sudo systemctl daemon-reload
sudo systemctl reset-failed
```

Ensures systemd picks up all changes from the previous steps and clears failed unit states.

### Step 9: Verification Scan

Runs a complete scan to verify the system is clean:

- Re-scans IOC database
- Re-checks PKGBUILD analysis
- Re-checks eBPF rootkit traces
- Re-checks systemd persistence
- Re-checks npm/bun cache

**Result:**
- 🟢 **Clean** — All threats removed. Monitor your system and rotate any remaining credentials.
- 🟡 **Suspicious** — Some indicators remain. Manual investigation needed.
- 🔴 **Still infected** — Reinstall recommended. The malware may have deeper persistence.

---

## After Recovery

Even if the verification scan shows clean:

1. **Monitor your system** for at least 1-2 weeks:
   - Check `journalctl -u arch-shield.service` for scan results
   - Watch for unexpected network connections (`ss -tulpn`)
   - Check for new systemd services (`systemctl list-units --type=service --state=running`)
2. **Change all passwords** — even if credential rotation was done, some credentials may have been exfiltrated before rotation
3. **Enable 2FA** on all accounts that support it
4. **Review GitHub/GitLab access logs** for unauthorized access
5. **Consider reinstalling** if an eBPF rootkit was detected — it's the only 100% reliable recovery

---

## Emergency Quick Reference

```bash
# 1. Run emergency recovery
./arch-shield.sh emergency

# 2. After recovery, verify
./arch-shield.sh scan

# 3. Re-enable protection
./arch-shield.sh protect

# 4. Check status
./arch-shield.sh status
```