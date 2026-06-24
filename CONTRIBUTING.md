# Contributing

Contributions to arch-shield are welcome! This guide explains how to contribute detection rules, IOC sources, code, and bug reports.

---

## Ways to Contribute

| Type | How |
|------|-----|
| 🐛 Bug report | [Open an Issue](https://github.com/leckminartor/arch-shield/issues) |
| ✨ Feature request | [Open an Issue](https://github.com/leckminartor/arch-shield/issues) with `feature-request` label |
| 🔔 False positive report | Open an Issue with package name, triggered rules, and PKGBUILD excerpt |
| 📋 New detection rules | Submit a PR (see below) |
| 🌐 New IOC source | Open an Issue with source URL and format details |
| 🐧 Distribution compatibility | Test on your distro and report results |
| 📖 Documentation | Submit PR for wiki/README improvements |
| 💻 Code improvements | Submit a PR |

---

## Contributing Detection Rules

The PKGBUILD scanner uses grep/regex-based rules. Each rule is defined with:

1. **Pattern** — The regex/grep pattern to match
2. **Name** — Short identifier (e.g., `REV_SHELL_BASH_TCP`)
3. **Description** — What the rule detects
4. **Severity** — `critical`, `warning`, or `info`
5. **Category** — `reverse_shell`, `credential_theft`, `ebpf_rootkit`, `cryptominer`, `obfuscation`, `network`, `filesystem`, `privilege_escalation`, `info_gathering`

### Adding a Rule

1. Fork the repo
2. Add your rule to the scanner's rule definitions in `arch-shield.sh`
3. Test your rule:
   - Against a known-malicious PKGBUILD → should trigger
   - Against a legitimate PKGBUILD → should NOT trigger
4. Submit a PR with:
   - The rule definition
   - Test cases (malicious and clean PKGBUILD excerpts)
   - Description of what it detects and why

### Rule Quality Guidelines

- **Minimize false positives** — test against common legitimate packages
- **Be specific** — don't match common patterns that appear in normal scripts
- **Comment your regex** — explain what it matches and why
- **Include edge cases** — obfuscated variants, encoding tricks

---

## Contributing IOC Sources

If you know of a reliable source for AUR malware indicators:

1. Open an [Issue](https://github.com/leckminartor/arch-shield/issues) with:
   - Source URL
   - Format (plain text, JSON, CSV, etc.)
   - How packages are identified as malicious
   - How frequently it's updated
   - Whether it's publicly accessible

**Requirements:**
- Must be publicly accessible (no auth required)
- Must list package names
- Must be actively maintained
- Must include methodology for identifying malicious packages

---

## Development Setup

```bash
# Clone the repo
git clone https://github.com/leckminartor/arch-shield.git
cd arch-shield

# Test in dry-run mode
./arch-shield.sh --dry-run all

# Test in a Distrobox container (recommended)
distrobox create --name arch-test --image archlinux:latest
distrobox enter arch-test
# Inside container:
sudo pacman -Syu base-devel git
./arch-shield.sh --dry-run all
```

---

## Code Style

This project follows Bash best practices:

| Practice | Rule |
|----------|------|
| Shell | `#!/usr/bin/env bash` |
| Shell options | `set -euo pipefail` (or equivalent safety mode) |
| Variables | Use `"${variable}"` — always quote |
| Functions | Use lowercase names, `function_name()` syntax |
| Comments | English, explain *why* not *what* |
| Error handling | Check exit codes, fail with clear messages |
| User input | Never trust — validate and sanitize |
| sudo | Use `sudo` for privileged ops, don't assume root |
| Portability | Avoid bashisms that break on other shells (script runs in bash only, but hooks may not) |

---

## Testing

### Before submitting a PR:

1. **Dry run passes:** `./arch-shield.sh --dry-run all` — no errors
2. **Scan works:** `./arch-shield.sh scan` — completes without crash
3. **Test in Distrobox:** Run in an Arch container to verify clean environment
4. **No false positives:** Test your changes against legitimate packages
5. **Shellcheck:** Run `shellcheck arch-shield.sh` — fix warnings

### Testing with simulated malware

For testing the emergency recovery module:

1. Create a test container: `distrobox create --name arch-test --image archlinux:latest`
2. Inside, simulate malware:
   - Create a fake infected package entry
   - Add a suspicious systemd service
   - Place a file in `/tmp/`
3. Run `./arch-shield.sh emergency`
4. Verify each step works correctly
5. Run `./arch-shield.sh scan` to verify cleanup

---

## Pull Request Process

1. Fork the repo and create a feature branch:
   ```bash
   git checkout -b feature/my-new-rule
   ```
2. Make your changes
3. Test thoroughly (see above)
4. Commit with a clear message:
   ```bash
   git commit -m "Add detection rule for <pattern> (category: <category>)"
   ```
5. Push and open a PR:
   ```bash
   git push origin feature/my-new-rule
   ```
6. In the PR description, include:
   - What was added/changed
   - Test results
   - Any false positive risks
   - Screenshots/output if applicable

---

## Issue Guidelines

### Bug Reports

Include:
- Distribution and version
- AUR helper and version
- Shell
- arch-shield version (`./arch-shield.sh help` shows version)
- Command that failed
- Full error output
- Output of `./arch-shield.sh --dry-run all` (if applicable)

### False Positive Reports

Include:
- Package name
- AUR URL
- Triggered rule names/IDs (from `./arch-shield.sh check <package>` output)
- PKGBUILD excerpt that triggered the rule
- Why you believe it's a false positive

### Feature Requests

Include:
- Use case (what problem does this solve?)
- Proposed solution
- Alternatives considered
- Whether you're willing to implement it yourself

---

## Code of Conduct

Be respectful, constructive, and patient. This is a volunteer project — everyone contributes their free time. Personal attacks, harassment, and toxic behavior will not be tolerated.