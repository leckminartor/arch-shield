# Changelog

All notable changes to arch-shield are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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