# Changelog

All notable changes to arch-shield are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.5.2] — 2026-09-05

### Fixed — Veraltete `/usr/bin/aur-scan`-Pfade (Fork-Installation)

Die generierten Pacman-Hooks und der Weekly-Timer referenzierten noch die alten `/usr/bin/`-Pfade des entfernten AUR-Pakets `aur-scanner`. Da die Binaries seit v1.5.0 aus dem Fork-Repo nach `/usr/local/bin/` installiert werden, brachen `paru`/`pacman` mit `Kann Abhängigkeiten nicht erfüllen` ab.

- **Post-Install-Hook** (`install_pacman_post_hook`): `Exec = /usr/bin/aur-scan system` → `/usr/local/bin/aur-scan system`; die fehlerhafte `Depends = aur-scanner`-Zeile entfernt (das AUR-Paket existiert nicht mehr — `Depends` ließ pacman die Transaktion abbrechen).
- **Pre-Install-Hook** (`install_pacman_pre_hook`): `Exec = /usr/bin/aur-scan-hook` → `/usr/local/bin/aur-scan-hook` (sowohl im manuellen `tee`-Hinweis als auch im installierten Hook); `command_exists`-Prüfung auf `/usr/local/bin/aur-scan-hook` korrigiert.
- **Weekly-Timer** (`install_weekly_timer`): `/usr/bin/aur-scan system` → `/usr/local/bin/aur-scan system`.
- **Version**: `SCRIPT_VERSION` 1.5.1 → 1.5.2.

### Verified

- **Dual-LLM-Code-Review**: Code-Qualität + Security-Architektur (2 parallele Reviews)
- **Getestet in frischer Arch-Distrobox** (`archlinux:latest`): Hook-Generierung, `bash -n`-Syntaxcheck, Pfad-Konsistenz (keine `/usr/bin/aur-scan`-Referenzen mehr).

## [1.5.1] — 2026-08-09

### Fixed — `build_dir: unbound variable` crash + wirkungsloses Temp-Cleanup

Ein echter Bug wurde beim Test in einer frischen Arch-Distrobox gefunden und behoben.

- **Crash am Ende von `protect`**: `install_aur_scanner()` nutzte eine `local build_dir`-Variable in einem `trap 'rm -rf "$build_dir"' RETURN`. Ein `RETURN`-Trap feuert auch beim Return des **Callers** erneut — dort ist die `local`-Variable bereits zerstört, sodass der Trap unter `set -u` mit `build_dir: unbound variable` crashte. Der `protect`-Lauf endete mit Exit-Code 1, obwohl alle 6 Schutzmaßnahmen erfolgreich installiert waren.
- **Wirkungsloses Cleanup**: Da `local`-Variablen beim Funktions-Return zerstört werden, war `${build_dir:-}` im Trap immer leer → `rm -rf ""` → No-op → das temporäre Build-Verzeichnis (`/tmp/arch-shield-aur-scanner-build.*`) leakte bei jedem Lauf.
- **Fix**: `build_dir` ist jetzt die **globale** Variable `AUR_SCAN_BUILD_DIR` (konsistent mit dem bestehenden `AUR_SCAN_CHECK_DIR`-Muster). Das Cleanup übernimmt der globale `cleanup_temp`-EXIT-Trap. Kein Crash, kein Temp-Dir-Leak.
- **Fehlerisolierung in `install_protection()`**: Die 6 Sub-Installationen werden jetzt mit `|| log_wrn "Schritt X/6 fehlgeschlagen — fahre fort"` abgesichert, damit ein Teilfehler nicht mehr den gesamten `protect`-Lauf abbricht (partielle Installation).
- **Temp-Datei-Leak in `install_auditd_monitoring()`**: `rules_file` wird jetzt auch bei `cp`-Fehler aufgeräumt.

### Verified

- **Dual-LLM-Code-Review**: Code-Qualität + Security-Architektur (2 parallele Reviews)
- **Getestet in frischer Arch-Distrobox** (`archlinux:latest`): `protect` läuft sauber (Exit 0, kein Crash, kein Temp-Dir-Leak), Malware-Erkennung (simuliertes `atomic-lockfile` im npm-Cache → KRITISCHER FUND) funktioniert, Idempotenz bestätigt.

## [1.5.0] — 2026-08-05

### Added — "Atomic Arch Wave 3" (July/Aug 2026) two-stage loader/stealer coverage

A third wave of the Atomic Arch campaign (AUR push lockdown since 2026-08-01)
uses a two-stage attack: a C loader executed as **root via
`sudo "$srcdir/optimizer"` inside `build()`** — *before* any pre-install hook can
scan it — which bootstraps a private Tor client, downloads a Rust
infostealer/RAT/SSH-worm from a `.onion` C2, and launches it via
`systemd-run --user --scope`. Stage 2 exfiltrates credentials/crypto/browser data
over Tor disguised as `argv[0]=dbus-daemon`.

- **New Wave-3 Loader-Check (emergency scan, step 6/7)**: Detects
  - private Tor bootstrap artifacts under `/tmp` (`/tmp/tb`, `/tmp/.torrc`)
  - stage-2 drop path `/dev/shm/.agent.bin`
  - Tor-exfil process masquerading as `dbus-daemon` (with `AllowSingleHopCircuits`)
  - `security.selinux` reinfection-marker xattr (value `0x01`) on `/etc/resolv.conf`, `/run/utmp`, etc.
  - Wave-3 systemd services (randomized names, `ExecStart` pointing at `/tmp/tb`/`.agent.bin`)
    including **transient units** started via `systemd-run`
- **C2 blocklist**: blocks `temp.sh` and `archive.torproject.org` (blocking the
  Tor-bundle download neuters the stage-1 loader). Deliberately does **not** block
  the whole `torproject.org` TLD, to avoid breaking legitimate Tor usage. The
  Wave-3 C2 `.onion` is documented in `/etc/hosts` for reference. Applies to both
  `install_c2_blocking()` and the daily-update script.
- **aur-scanner upgraded to v2.2.0** in `install_aur_scanner()` — includes the
  new ATOMIC-005..010 Wave-3 detection rules.

### Changed
- Scan step numbering updated to [7/7] (new Wave-3 check inserted).
- Hardcoded detection-rule count corrected from "118" to "87" (actual builtin rules).
- Daily-update C2 rewrite uses `RUN_SU` (root/sudo/doas) instead of hardcoded `sudo`.

### Verified
- **Dual-LLM code review** (code-quality + security-architecture) — all HIGH and
  CRITICAL findings addressed (C2-blocklist collateral damage, xattr value check,
  transient-unit coverage, `RUN_SU` privilege handling).
- **Tested in a fresh Arch Distrobox container** (`aur-shield-test`,
  `archlinux:latest`): `bash -n` passes, `arch-shield.sh --dry-run status` runs,
  aur-scanner v2.2.0 scans simulated Wave-3 loaders correctly.
- aur-scanner v2.2.0: full workspace test suite passes (**275 tests**, incl.
  ATOMIC-005..010 positive/negative cases).

---

## [1.4.6] — 2026-07-11

### Fixed — install_aur_scanner() hardened per security review

| Issue | Fix |
|-------|-----|
| SUDO_BIN hardcoded to sudo — broke doas support | Preserve find_sudo() result; never overwrite SUDO_BIN |
| Temp dir fallback race condition (fixed path) | mktemp -d only; trap + RETURN for atomic cleanup |
| cargo build --all deprecated since 2020 | --workspace instead |
| --locked without checking Cargo.lock | Only add --locked when Cargo.lock exists |
| rust package name assumed for all distros | Manjaro uses rustup; auto-detected via DISTRO_ID |
| Path typo /usr/share/aur-scanner/ | Consistent /usr/share/aur-scan/ everywhere |
| cd error ignored | cd build_dir || { log_err ...; return 1; } |
| trap missing for build dir cleanup | trap rm -rf build_dir RETURN |

### Verified
- Distrobox Arch Linux: `cargo build --release --workspace` → success
- `aur-scan` 2.1.0 runs correctly
- arch-shield.sh v1.4.6 starts, menus work

---

## [1.4.5] — 2026-07-10

### Added — aur-scanner jetzt aus Fork-Repo (v2.1.0)

- `install_aur_scanner()` baut **nicht mehr** das veraltete AUR-Paket `aur-scanner` (v2.0.0), sondern **direkt aus dem leckminartor-Fork**:
  https://github.com/leckminartor/ks-aur-scanner.git (Tag `v2.1.0`)
- Enthält alle **Atomic-Arch-5-Wave-Erkennungen** (v2.1.0)

### Atomic-Arch 5-Wave Coverage (v2.1.0)
| Wave | Angriffsmethode | Erkennung |
|------|----------------|-----------|
| W1 | `npm install atomic-lockfile` | ATOMIC-001 + ATOMIC-002 |
| W2 | `bun add js-digest` + `.hook` Files | ATOMIC-001/002 + **.hook-Scanning** |
| W3 | Obfuscated `bun add nextfile-js` | ATOMIC-001 erweitert + De-obfuscation |
| W4 | ALPM `.hook` File Delivery | **NEU: .hook File Discovery** |
| W5 | Shell-RC Injection (fish/zsh/profile.d) | ENV-003 erweitert |
| — | `~/.local/bin/sudo` Credential Shim | **NEU: ATOMIC-004** |

### Verified
- Build in Distrobox Arch Linux (Rust 1.96.0) — 6m 48s
- `aur-scan` 2.1.0 läuft korrekt
- arch-shield.sh v1.4.5 startet, erkennt Distro/Shell, Menüs funktionieren

---

## [1.4.4] — 2026-06-26

### Fixed
- **Critical**: Pre-Install Hook broke `cachy-update` when paru builds AUR packages in aurbuild chroot
- Hook had `AbortOnFail` but no binary existence check — `call to execv failed` in chroot
- Fix: `/bin/sh -c` wrapper gracefully skips hook when `aur-scan-hook` binary is absent
- `AbortOnFail` preserved on host — malware detection still blocks transactions

### Changed
- `install_pacman_pre_hook()`: validates hook content (not just existence) before skipping — auto-updates outdated hooks
- `install_pacman_post_hook()`: same content validation
- `show_status()`: shows ⚠ warning for outdated hooks

### Verified
- Live test: `cachy-update` + `paru -S google-chrome` working
- Chroot test: `mkarchroot` installs 152 packages without abort
- Dual LLM review: both APPROVED (qwen3-coder + deepseek)
- Pacman source code analysis: `alpm_wordsplit()` correctly handles single-quotes

---

## [1.4.3] — 2026-06-23

### Fixed
- 5 findings from dual code review (qwen3-coder:480b + deepseek-v4-pro)
- Quoting issues in several variables
- Race condition in pacman hook execution
- Robustness improvements in error handling

### Changed
- Improved error messages for missing dependencies
- Enhanced dry-run output for better readability

---

## [1.3.0] — 2026-06-23

### Added
- 🛡️ **Protection module** — Shell integration (bash, zsh, fish, nu), pacman pre/post-install hooks, weekly systemd timer
- 🔧 **Hardening module** — eBPF hardening via sysctl, build isolation (paru chroot), repo SigLevel verification, AUR helper configuration
- 🚨 **Emergency recovery** — Guided 9-step recovery for confirmed infections
- 🔄 **Threat-intel update** — IOC database updates from community feeds (git pull, HedgeDoc, Arch News)
- 📊 **Status module** — Overview of all installed protection measures
- 📦 **Package check** — Check individual AUR package against all databases
- `--dry-run` mode for all commands
- Haftungsausschluss (disclaimer: no warranty, no liability, use at own risk)
- SECURITY-GUIDE.md

### Changed
- Expanded IOC database integration (1,935+ known infected packages)
- Enhanced PKGBUILD analysis (118 detection rules)
- Improved scan output with color-coded results

---

## [1.0.0] — 2026-06-22

### Added
- 🔍 **System scan** — 6-layer scan: IOC packages, PKGBUILD analysis, eBPF rootkit, npm/bun cache, systemd persistence, pacman log
- Interactive menu
- Basic command-line interface (`scan`, `all`, `help`)
- GPL-3.0-or-later license
- Initial README
- Response to Atomic-Arch Supply-Chain Attack (June 2026)

---

## Version History Summary

| Version | Date | Key Features |
|---------|------|--------------|
| 1.0.0 | 2026-06-22 | Initial release: System scan, 6-layer detection |
| 1.3.0 | 2026-06-23 | Protection, hardening, emergency recovery, threat-intel updates |
| 1.4.3 | 2026-06-23 | Code review fixes (qwen3-coder + deepseek-v4-pro) |
| 1.4.4 | 2026-06-26 | Pre-Install Hook chroot fix (/bin/sh -c wrapper) |
| 1.4.5 | 2026-07-10 | aur-scanner aus Fork-Repo gebaut (v2.1.0, Atomic-Arch-5-Wave-Coverage) |
| 1.4.6 | 2026-07-11 | install_aur_scanner() gehärtet (Security-Review: SUDO_BIN, mktemp-Race, --workspace, --locked bedingt, Pfad-Typos) |
| 1.5.0 | 2026-08-05 | Wave-3 loader/stealer coverage (Tor-C2, stage-2, dbus masquerade), C2 blocklist + torproject.org, aur-scanner v2.2.0 |
| 1.5.1 | 2026-08-09 | Fix: `build_dir: unbound variable` crash + wirkungsloses Temp-Cleanup (globale Variable + EXIT-Trap), Fehlerisolierung in install_protection(), rules_file-Leak behoben |
| 1.5.2 | 2026-09-05 | Fix: veraltete `/usr/bin/aur-scan`-Pfade in Pacman-Hooks + Weekly-Timer → `/usr/local/bin/` (Fork-Installation), `Depends = aur-scanner` aus Post-Install-Hook entfernt |

---

## Roadmap (Future)

### Planned
- [ ] Additional IOC sources
- [ ] Nushell shell integration improvements
- [ ] aarch64 architecture testing
- [ ] Additional PKGBUILD detection rules
- [ ] Configuration file for customizing scan behavior
- [ ] JSON output mode for programmatic use
- [ ] Integration with more AUR helpers (aura, pakku)

### Under Consideration
- [ ] GUI wrapper (TUI via dialog/whiptail)
- [ ] Automatic credential rotation assistance
- [ ] Integration with Arch Linux's official security tracker
- [ ] Support for non-systemd init systems (Artix OpenRC/runit)
- [ ] Package version pinning for known-safe versions

---

*For detailed commit history, see [GitHub commits](https://github.com/leckminartor/arch-shield/commits).*