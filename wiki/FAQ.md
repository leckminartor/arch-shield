# FAQ

## General

### Is arch-shield a replacement for manual PKGBUILD review?

**No.** arch-shield is a supplement, not a replacement. The AUR is an unofficial, community-maintained repository. The only safe usage requires reviewing every line in `PKGBUILD` and `.install` files before installation. arch-shield adds automated detection on top of that, but cannot guarantee 100% protection.

### Does arch-shield guarantee 100% protection?

**No.** There is no guarantee of 100% protection against all threats. New malware patterns may not be in the detection rules yet, and sophisticated obfuscation can evade static analysis. arch-shield catches known threats and common patterns — it's a first line of defense, not a silver bullet.

### Is arch-shield an antivirus?

**No.** It's a specialized AUR security tool, not a general-purpose antivirus. It focuses specifically on AUR supply-chain attacks, PKGBUILD malware, and eBPF rootkits. For general antivirus, consider ClamAV or other tools — they complement each other.

### Can I use arch-shield on non-Arch distributions?

**No.** arch-shield is specifically designed for Arch Linux and Arch-based distributions. It relies on `pacman`, AUR helpers, and Arch-specific configuration paths. It won't work on Debian, Fedora, openSUSE, etc.

---

## Usage

### Should I run `--dry-run` first?

**Yes, always.** On a new system or after updates, run `./arch-shield.sh --dry-run all` first to preview what changes would be made. This is especially important before running `harden` which modifies sysctl settings.

### What's the difference between `scan` and `check`?

- **`scan`** — Scans your entire system (all installed packages, all 6 layers)
- **`check <package>`** — Checks a single package against the databases (quick, targeted)

Use `check` before installing a suspicious package. Use `scan` for regular system audits.

### How often should I scan?

- **Weekly** — the systemd timer handles this automatically (every Monday)
- **After installing AUR packages** — the post-install hook handles this automatically
- **After the weekly timer runs** — check `journalctl -u arch-shield.service` for results

### What happens if the pre-install hook blocks a package I need?

The hook uses `AbortOnFail` — it aborts the entire transaction. If you believe it's a false positive:

1. Check the package with `./arch-shield.sh check <package>` to see which rule triggered
2. Review the PKGBUILD manually
3. If you're confident it's safe, you can temporarily remove the hook:
   ```bash
   sudo mv /etc/pacman.d/hooks/aur-shield-pre-install.hook /tmp/
   sudo pacman -S <package>
   sudo mv /tmp/aur-shield-pre-install.hook /etc/pacman.d/hooks/
   ```
4. Open an Issue to report the false positive

### Can I run arch-shield without sudo?

- `scan` — works without sudo (some checks may be limited)
- `check` — works without sudo
- `status` — works without sudo
- `protect` — **needs sudo** (installs system hooks, systemd timer)
- `harden` — **needs sudo** (modifies sysctl, system config)
- `emergency` — **needs sudo** (removes packages, services)
- `update` — works without sudo (if aur-malware-check is in user directory)

---

## Emergency

### I think I'm infected. What should I do?

1. **Don't panic.** Run `./arch-shield.sh scan` first to confirm.
2. If infected: `./arch-shield.sh emergency` — follow the 9-step guided recovery.
3. After recovery: `./arch-shield.sh scan` to verify.
4. If an eBPF rootkit was detected: **reinstall your system** — it's the only reliable recovery.

### The emergency module found an eBPF rootkit. Should I reinstall?

**Yes.** eBPF rootkits can hide processes, files, and network connections from the kernel itself. Even after cleanup, you cannot fully trust a system that had an active eBPF rootkit. Backup your data, reinstall, and rotate all credentials.

### The verification scan after recovery still shows suspicious items. What now?

This means the malware has deeper persistence or the cleanup didn't catch everything. Options:
1. Run `./arch-shield.sh emergency` again
2. Manual investigation of the remaining suspicious items
3. **Reinstall the system** — the safest option

---

## Technical

### Why Bash and not Python?

Bash is available on every Arch system by default — no Python dependencies needed. The script is a single file that's easy to audit, easy to run, and has zero installation overhead. For a security tool, simplicity and transparency matter.

### How does the PKGBUILD scanner work?

The scanner performs static analysis on PKGBUILD files using 118 grep/regex-based rules. Each rule matches a known malicious pattern (reverse shell, credential theft, eBPF rootkit, etc.). The rules are categorized by severity (Critical, Warning, Info).

### Can I add my own detection rules?

Yes! See the [Contributing](Contributing) page. You can add rules to the scanner by submitting a PR with:
- The detection pattern (regex/grep)
- The rule name and description
- Severity level
- Test cases (malicious PKGBUILD that triggers it, clean PKGBUILD that doesn't)

### How large is the IOC database?

As of v1.4.3, the IOC database contains 1,935+ known infected package names. It's sourced from the community-maintained [aur-malware-check](https://github.com/lenucksi/aur-malware-check) project and updated weekly via the systemd timer.

### Does arch-shield send any data anywhere?

**No.** arch-shield is completely offline — it does not phone home, send telemetry, or report any data. All scanning is done locally. The only network activity is:
- `git pull` for aur-malware-check updates (you initiate this)
- Fetching Arch Linux news RSS during `update`
- Fetching HedgeDoc community feeds during `update`

---

## Uninstallation

### How do I completely remove arch-shield?

1. Remove shell integration (check `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, `~/.config/nushell/env.nu`)
2. Remove pacman hooks:
   ```bash
   sudo rm /etc/pacman.d/hooks/aur-shield-pre-install.hook
   sudo rm /etc/pacman.d/hooks/aur-shield-post-install.hook
   ```
3. Remove systemd timer:
   ```bash
   sudo systemctl disable --now arch-shield.timer
   sudo rm /etc/systemd/system/arch-shield.{service,timer}
   sudo systemctl daemon-reload
   ```
4. Revert sysctl changes (if applied):
   ```bash
   sudo sysctl -w kernel.unprivileged_bpf_disabled=0
   sudo sysctl -w net.core.bpf_jit_harden=0
   sudo sysctl -w kernel.kptr_restrict=1
   ```
5. Remove aur-scanner and aur-malware-check if installed
6. Delete `arch-shield.sh`