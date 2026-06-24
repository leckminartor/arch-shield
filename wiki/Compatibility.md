# Compatibility

## Supported Distributions

arch-shield is designed for all Arch Linux-based distributions on x86_64.

| Distribution | Status | Notes |
|-------------|--------|-------|
| **Arch Linux** | ✅ Fully supported | Primary development target |
| **CachyOS** | ✅ Fully supported | Tested with paru |
| **EndeavourOS** | ✅ Fully supported | Tested with yay |
| **Manjaro** | ✅ Supported | Uses its own repos + AUR; SigLevel config may differ |
| **Garuda Linux** | ✅ Supported | Uses chaotic-aur repo; extra repos won't interfere |
| **Artix Linux** | ⚠️ Partially supported | No systemd — timer and systemd hooks won't work; scan & harden still functional |

### Artix Linux Limitations

Artix uses OpenRC or runit instead of systemd. This means:
- ❌ **systemd timer** — not available (use cron or OpenRC service instead)
- ❌ **Pacman hooks via systemd** — not available (hooks still work as they're pacman-level, not systemd-level)
- ✅ **System scan** — fully functional
- ✅ **PKGBUILD analysis** — fully functional
- ✅ **eBPF hardening** — fully functional (sysctl is kernel-level, not systemd)
- ✅ **IOC database check** — fully functional
- ⚠️ **Shell integration** — works, but manual cron setup needed for auto-scan

---

## AUR Helper Compatibility

| Helper | Shell Integration | Build Isolation | Status |
|--------|-------------------|-----------------|--------|
| **paru** | ✅ | ✅ (chroot mode) | Recommended — best integration |
| **yay** | ✅ | ⚠️ (manual chroot) | Fully supported |
| **pikaur** | ✅ | ⚠️ | Supported |
| **trizen** | ✅ | ⚠️ | Supported |
| **aura** | ⚠️ | ⚠️ | Not explicitly tested — should work for scan |
| **No helper** | N/A | N/A | Scan & harden work; shell integration skipped |

---

## Shell Compatibility

| Shell | Shell Integration | Status |
|-------|-------------------|--------|
| **bash** | ✅ | Fully supported (4+) |
| **zsh** | ✅ | Fully supported |
| **fish** | ✅ | Fully supported |
| **Nushell (nu)** | ✅ | Fully supported |
| **Other** | ❌ | Not supported — open an Issue with your shell |

---

## Architecture

| Architecture | Status |
|-------------|--------|
| **x86_64** | ✅ Fully supported |
| **aarch64** | ⚠️ Should work, but untested |
| **i686** | ⚠️ Should work, but untested |
| **RISC-V** | ❌ Not tested |

---

## Known Issues

### Manjaro: SigLevel warnings
Manjaro uses its own repository signing keys alongside Arch's. The repo SigLevel check may show warnings for Manjaro-specific repos. This is expected — verify that Manjaro's own repos are properly signed.

### Garuda Linux: chaotic-aur repo
Garuda includes the chaotic-aur repository which is pre-compiled. Packages from chaotic-aur are not checked by the PKGBUILD scanner (they're already built). IOC database check still works. Consider this when relying on arch-shield with Garuda.

### CachyOS: Custom kernel
CachyOS uses a custom kernel. Some sysctl keys may have different defaults. The hardening module checks current values before applying and skips if already hardened.

### EndeavourOS: AUR helper defaults
EndeavourOS ships with yay as default. The script detects this and configures yay accordingly.

---

## Testing Environments

arch-shield has been tested in:

| Environment | Method |
|-------------|--------|
| Distrobox Arch container | Primary testing environment (scan, emergency recovery with simulated malware) |
| Bare metal Arch Linux | Real-world testing |
| CachyOS VM | Compatibility testing |
| EndeavourOS VM | Compatibility testing |

---

## Reporting Compatibility Issues

If arch-shield doesn't work on your distribution or shows unexpected behavior:

1. Run `./arch-shield.sh --dry-run all` and capture the output
2. Run `./arch-shield.sh status` and capture the output
3. Open an [Issue](https://github.com/leckminartor/arch-shield/issues) with:
   - Distribution name and version
   - AUR helper (if any)
   - Shell
   - Output of `./arch-shield.sh --dry-run all`
   - Output of `./arch-shield.sh status`
   - Description of the problem