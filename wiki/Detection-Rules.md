# Detection Rules

arch-shield's PKGBUILD scanner uses **87 static detection rules** to identify malicious patterns in AUR PKGBUILDs and `.install` files. These rules are organized into categories.

---

## Rule Categories

### 🔴 Reverse Shells (12 rules)

Detects common reverse shell patterns that give attackers remote access to your system.

**Examples of detected patterns:**
- `bash -i >& /dev/tcp/` — Classic bash reverse shell
- `nc -e /bin/bash` — Netcat reverse shell
- `python -c 'import socket,subprocess,os` — Python reverse shell
- `socat TCP:` — Socat-based reverse shell
- Base64-encoded reverse shell payloads
- Obfuscated reverse shell variants

### 🔴 Credential Theft (18 rules)

Detects patterns that exfiltrate credentials (SSH keys, GPG keys, browser data, environment variables).

**Examples:**
- Reads `~/.ssh/` directory contents
- Accesses `~/.gnupg/` (GPG keys)
- Sends data to external URLs via `curl`/`wget` with POST
- Reads environment variables containing `TOKEN`, `KEY`, `SECRET`, `PASSWORD`
- Accesses browser data directories (Chrome, Firefox, etc.)
- Reads `~/.aws/credentials`, `~/.docker/config.json`
- Clipboard access (`xclip`, `xsel`)

### 🔴 eBPF Rootkit (10 rules)

Detects patterns related to the eBPF rootkit used in the Atomic-Arch attack.

**Examples:**
- Loads BPF programs via `bpftool` or direct syscalls
- Creates entries in `/sys/fs/bpf/`
- References to `hidden_maps`, `hidden_progs`
- BPF object file loading (`*.o` BPF programs)
- `bpf_attach`, `bpf_prog_load` patterns
- Modifications to `/proc/sys/kernel/unprivileged_bpf_disabled`

### 🔴 Cryptominers (15 rules)

Detects cryptocurrency mining malware.

**Examples:**
- Downloads and executes known miners (xmrig, cpuminer, etc.)
- References to mining pools (`stratum+tcp://`, `stratum+ssl://`)
- CPU affinity pinning for mining
- `nicehash`, `monero`, `randomx` references in build scripts
- Obfuscated miner download URLs
- Systemd services with `Restart=always` combined with mining patterns

### 🟡 Obfuscation (20 rules)

Detects code obfuscation techniques commonly used to hide malicious behavior.

**Examples:**
- Base64-encoded strings decoded at runtime (`eval $(echo "..." | base64 -d)`)
- Hex-encoded payloads (`\x2f\x62\x69\x6e\x2f...`)
- Variable name randomization (`a1b2c3`, `x_y_z_123`)
- `tr` command for character substitution obfuscation
- Multiple nested `eval` statements
- Environment variable manipulation for obfuscation
- `sed`/`awk` used to reconstruct strings
- Whitespace and comment injection to break pattern matching

### 🟡 Suspicious Network Activity (14 rules)

Detects unauthorized network communication.

**Examples:**
- `curl`/`wget` with `-O-` piped to `bash` (download-and-execute)
- Hardcoded IP addresses (non-standard, non-RFC1918)
- `scp`/`rsync` to external hosts
- DNS exfiltration patterns
- Tor hidden service connections (`.onion` URLs)
- Non-standard port usage for data exfiltration
- `iptables`/`nftables` rules that allow outbound on unusual ports

### 🟡 Suspicious File Operations (12 rules)

Detects filesystem manipulation associated with malware.

**Examples:**
- Writes to `/etc/cron.d/`, `/etc/cron.daily/`
- Modifies `/etc/passwd`, `/etc/shadow`
- Writes to `/etc/ld.so.preload` (library preloading for persistence)
- Creates systemd services in user directories (`~/.config/systemd/`)
- Modifies `~/.bashrc`, `~/.zshrc`, `~/.profile` with suspicious content
- Writes to `/etc/ld.so.conf.d/`

### 🟡 Privilege Escalation (8 rules)

Detects patterns that attempt to gain elevated privileges.

**Examples:**
- SUID bit setting on unusual binaries (`chmod u+s`)
- `sudo` commands in PKGBUILD (should never be needed)
- `doas` commands in PKGBUILD
- Modifications to `sudoers` file
- Polkit policy additions
- Capabilities setting (`setcap cap_sys_admin+ep`)

### 🟢 Information Gathering (9 rules)

Lower severity — detects patterns that gather system information (precursor to targeted attacks).

**Examples:**
- `uname -a`, `id`, `whoami` output sent to remote URLs
- System enumeration commands (`lsb_release`, `cat /etc/os-release`)
- Installed software enumeration
- Hardware information gathering (`lscpu`, `lspci`, `lsblk`)
- Network interface enumeration (`ip addr`, `ifconfig`)

---

## Rule Severity Levels

| Level | Color | Meaning | Action |
|-------|-------|---------|--------|
| 🔴 Critical | Red | Malicious behavior confirmed | Block installation (AbortOnFail) |
| 🟡 Warning | Yellow | Suspicious — needs manual review | Warn user, ask for confirmation |
| 🟢 Info | Green | Information gathering detected | Log and report, don't block |

---

## False Positives

Some legitimate packages may trigger detection rules. Common false positive sources:

- **System monitoring tools** (htop, btop) — may trigger information gathering rules
- **Network utilities** (curl, wget) — may trigger suspicious network rules
- **Security tools** (nmap, wireshark) — may trigger reverse shell / network rules
- **eBPF tools** (bcc, bpftrace) — may trigger eBPF rootkit rules

### How to report false positives:

1. Run `./arch-shield.sh check <package>` to see which rules triggered
2. Review the flagged PKGBUILD lines manually
3. If safe, open an [Issue](https://github.com/leckminartor/arch-shield/issues) with:
   - Package name
   - Triggered rule IDs
   - PKGBUILD excerpt
   - Why you believe it's a false positive

---

## Contributing New Rules

To contribute new detection rules:

1. Identify a malicious pattern not yet covered
2. Write a detection rule (grep/regex pattern)
3. Test against known-malicious PKGBUILDs (should trigger)
4. Test against legitimate PKGBUILDs (should NOT trigger)
5. Submit a PR with the rule and test cases

See [Contributing](Contributing) for details.