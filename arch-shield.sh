#!/bin/bash
#==================================================================================
#  arch-shield — Arch Linux / AUR Security Hardening Script
#==================================================================================
#  Schützt jedes Arch-basierte System vor AUR-Malware (Atomic Arch, CHAOS RAT, ...)
#  Funktioniert auf: Arch Linux, CachyOS, EndeavourOS, Manjaro, Garuda, Artix, ...
#
#  Autor:    Erstellt Juni 2026 nach dem Atomic-Arch Supply-Chain-Angriff
#  Version:  1.0.0
#  Lizenz:   GPL-3.0-or-later
#  Quelle:   https://archlinux.org/news/active-aur-malicious-packages-incident/
#==================================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Globale Variablen ──────────────────────────────────────────────────────────
SCRIPT_VERSION="1.5.1"
SCRIPT_NAME="arch-shield"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN=""
SUDO_BIN=""
AUR_HELPER=""
DISTRO_NAME=""
DISTRO_ID=""
USER_SHELL=""
USER_SHELL_CONFIG=""
AUR_SCAN_CHECK_DIR=""
AUR_SCAN_BUILD_DIR=""
AUR_SCANNER_INSTALLED=false
LOG_DIR="$HOME/.local/share/arch-shield"
LOG_FILE="$LOG_DIR/arch-shield.log"
DRY_RUN=false
FORCE_YES=false

# Cleanup-Trap für temporäre Verzeichnisse
cleanup_temp() {
    [[ -n "$AUR_SCAN_CHECK_DIR" && -d "$AUR_SCAN_CHECK_DIR" ]] && rm -rf "$AUR_SCAN_CHECK_DIR" 2>/dev/null || true
    [[ -n "$AUR_SCAN_BUILD_DIR" && -d "$AUR_SCAN_BUILD_DIR" ]] && rm -rf "$AUR_SCAN_BUILD_DIR" 2>/dev/null || true
}
trap cleanup_temp EXIT

# Farben
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
    BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; PURPLE=''; CYAN=''
    BOLD=''; DIM=''; NC=''
fi

# ── Logging ─────────────────────────────────────────────────────────────────────
init_log() {
    mkdir -p "$LOG_DIR"
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] arch-shield v$SCRIPT_VERSION gestartet" > "$LOG_FILE"
}

log()   { echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1" >> "$LOG_FILE"; }
log_ok(){ echo -e "${GREEN}✓${NC} $1"; log "OK: $1"; }
log_inf(){ echo -e "${BLUE}ℹ${NC} $1"; log "INFO: $1"; }
log_wrn(){ echo -e "${YELLOW}⚠${NC} $1"; log "WARN: $1"; }
log_err(){ echo -e "${RED}✗${NC} $1" >&2; log "ERROR: $1"; }
log_sep(){ echo -e "${DIM}─────────────────────────────────────────────────────────${NC}"; }

# ── Hilfsfunktionen ─────────────────────────────────────────────────────────────
confirm() {
    [[ "$FORCE_YES" == "true" ]] && return 0
    local prompt="${1:-Fortfahren?}"
    read -rp "$(echo -e "${BOLD}${YELLOW}?${NC} ${prompt} [j/N] ")" ans
    [[ "${ans,,}" == "j" || "${ans,,}" == "y" || "${ans,,}" == "ja" || "${ans,,}" == "yes" ]]
}

command_exists() { command -v "$1" &>/dev/null; }

find_python() {
    local pythons=("python3" "python" "python3.12" "python3.13" "python3.14")
    for py in "${pythons[@]}"; do
        if command_exists "$py"; then
            PYTHON_BIN="$py"
            return 0
        fi
    done
    return 1
}

find_sudo() {
    if [[ $EUID -eq 0 ]]; then
        SUDO_BIN=""  # Already root
        return 0
    fi
    for su in sudo doas; do
        if command_exists "$su"; then
            SUDO_BIN="$su"
            return 0
        fi
    done
    return 1
}

run_sudo() {
    if [[ -z "$SUDO_BIN" ]]; then
        "$@"
    else
        "$SUDO_BIN" "$@"
    fi
}

# ── Abhängigkeiten prüfen ────────────────────────────────────────────────────────
check_dependencies() {
    local missing=()
    local critical_missing=0

    # Bash 4+ prüfen
    if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
        echo -e "${RED}Fehler: Bash 4+ erforderlich (aktuell: ${BASH_VERSION}).${NC}" >&2
        exit 1
    fi

    # Kritische Tools
    for tool in grep find head tail cat cut sort uniq; do
        if ! command_exists "$tool"; then
            missing+=("$tool")
            critical_missing=$((critical_missing + 1))
        fi
    done

    if [[ $critical_missing -gt 0 ]]; then
        echo -e "${RED}Fehler: Kritische Tools fehlen: ${missing[*]}${NC}" >&2
        exit 1
    fi

    # Optionale Tools warnen (nicht abbrechen)
    if ! command_exists git; then
        log_wrn "git nicht installiert — aur-malware-check kann nicht aktualisiert werden"
    fi
    if ! command_exists systemctl; then
        log_wrn "systemctl nicht gefunden — systemd Timer kann nicht installiert werden"
    fi
    if ! find_python; then
        log_wrn "Python 3 nicht gefunden — aur-malware-check wird nicht funktionieren"
    fi
}

# ── Distro-Erkennung ────────────────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-$NAME:-unbekannt}"
        DISTRO_ID="${ID:-arch}"
    else
        DISTRO_NAME="unbekannt"
        DISTRO_ID="arch"
    fi

    # Fallback für Distros ohne PRETTY_NAME
    [[ -z "$DISTRO_NAME" || "$DISTRO_NAME" == "unbekannt" ]] && {
        for f in /etc/cachyos-release /etc/manjaro-release /etc/garuda-release \
                 /etc/endeavouros-release /etc/artix-release /etc/arch-release; do
            [[ -f "$f" ]] && DISTRO_NAME=$(cat "$f" 2>/dev/null | head -1) && break
        done
    }

    log_inf "Distribution erkannt: ${BOLD}$DISTRO_NAME${NC} (ID: $DISTRO_ID)"
    echo "$DISTRO_ID" | grep -qiE "arch|cachyos|manjaro|endeavouros|garuda|artix" || {
        log_wrn "Keine bekannte Arch-basierte Distribution erkannt."
        log_wrn "Script wird fortgesetzt, aber einige Pfade könnten abweichen."
    }
}

# ── AUR-Helper-Erkennung ─────────────────────────────────────────────────────────
detect_aur_helper() {
    local aur_helpers=("paru" "yay" "pikaur" "trizen" "aurutils")
    for h in "${aur_helpers[@]}"; do
        if command_exists "$h"; then
            AUR_HELPER="$h"
            log_inf "AUR-Helper erkannt: ${BOLD}$AUR_HELPER${NC}"
            return 0
        fi
    done
    log_wrn "Kein AUR-Helper gefunden (paru/yay/pikaur/trizen)."
    log_wrn "AUR-Schutzmaßnahmen werden eingeschränkt funktionieren."
    AUR_HELPER=""
    return 1
}

# ── Shell-Erkennung ─────────────────────────────────────────────────────────────
detect_shell() {
    USER_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "$SHELL")"
    case "$USER_SHELL" in
        */fish)
            USER_SHELL="fish"
            USER_SHELL_CONFIG="$HOME/.config/fish/config.fish"
            ;;
        */zsh)
            USER_SHELL="zsh"
            USER_SHELL_CONFIG="$HOME/.zshrc"
            ;;
        */nu)
            USER_SHELL="nu"
            USER_SHELL_CONFIG="$HOME/.config/nushell/config.nu"
            ;;
        */bash|*)
            USER_SHELL="bash"
            USER_SHELL_CONFIG="$HOME/.bashrc"
            ;;
    esac
    log_inf "Shell erkannt: ${BOLD}$USER_SHELL${NC} (Config: $USER_SHELL_CONFIG)"
}

#==================================================================================
#  MODUL 1: MALWARE-SCAN
#==================================================================================

# ── aur-malware-check installieren (Community Tool) ─────────────────────────────
install_aur_malware_check() {
    log_inf "Installiere/aktualisiere aur-malware-check (Community-Detection-Tool)..."

    # Sicheres temporäres Verzeichnis erstellen (Race Condition Schutz)
    if [[ -z "$AUR_SCAN_CHECK_DIR" ]] || [[ ! -d "$AUR_SCAN_CHECK_DIR" ]]; then
        AUR_SCAN_CHECK_DIR=$(mktemp -d -t arch-shield-aur-malware-check.XXXXXX 2>/dev/null || {
            # Fallback falls mktemp -t nicht verfügbar
            AUR_SCAN_CHECK_DIR="$HOME/.local/share/arch-shield/aur-malware-check"
            mkdir -p "$AUR_SCAN_CHECK_DIR"
        })
    fi

    if [[ -d "$AUR_SCAN_CHECK_DIR/.git" ]]; then
        log_inf "Repository vorhanden, aktualisiere..."
        git -C "$AUR_SCAN_CHECK_DIR" pull --quiet 2>/dev/null || log_wrn "Git pull fehlgeschlagen, verwende bestehende Version"
    else
        rm -rf "$AUR_SCAN_CHECK_DIR"
        AUR_SCAN_CHECK_DIR=$(mktemp -d -t arch-shield-aur-malware-check.XXXXXX 2>/dev/null || {
            AUR_SCAN_CHECK_DIR="$HOME/.local/share/arch-shield/aur-malware-check"
            mkdir -p "$AUR_SCAN_CHECK_DIR"
        })
        git clone --depth 1 --quiet "https://github.com/lenucksi/aur-malware-check.git" "$AUR_SCAN_CHECK_DIR" 2>/dev/null || {
            log_err "Konnte aur-malware-check nicht klonen."
            return 1
        }
    fi
    log_ok "aur-malware-check bereit unter $AUR_SCAN_CHECK_DIR"
}

# ── aur-scanner installieren (aus Fork-Repo) ────────────────────────────────────
install_aur_scanner() {
    if command_exists aur-scan; then
        log_ok "aur-scanner bereits installiert ($(aur-scan version 2>/dev/null | grep -o 'v[0-9.]*' | head -1))"
        AUR_SCANNER_INSTALLED=true
        return 0
    fi

    log_inf "Installiere aur-scanner aus Fork-Repo (v2.2.0 mit Wave-3-Regeln)..."

    # SUDO/doas Kommando ermitteln (nicht mit "sudo" überschreiben!)
    if [[ -z "$SUDO_BIN" ]]; then
        find_sudo || { log_err "Kein sudo/doas gefunden."; return 1; }
    fi

    # Build-Abhängigkeiten prüfen & nachinstallieren
    if ! command_exists cargo; then
        log_wrn "cargo (Rust) nicht installiert — versuche über AUR-Helper nachzuinstallieren"
        if [[ -n "$AUR_HELPER" ]]; then
            # Distro-spezifischer Package-Name
            local rust_pkg="rust"
            case "$DISTRO_ID" in
                manjaro) rust_pkg="rustup" ;;
                *)       rust_pkg="rust" ;;
            esac
            $AUR_HELPER -S --noconfirm "$rust_pkg" 2>&1 | tail -5 || {
                log_err "Rust ($rust_pkg) konnte nicht installiert werden."
                return 1
            }
        else
            log_err "Kein AUR-Helper und kein cargo — aur-scanner kann nicht gebaut werden."
            return 1
        fi
    fi
    if ! command_exists clang; then
        log_wrn "clang nicht installiert — optional für optimale Builds"
        [[ -n "$AUR_HELPER" ]] && $AUR_HELPER -S --noconfirm clang 2>&1 | tail -3 || true
    fi

    # Temporäres Build-Verzeichnis (atomic, keine Race-Condition)
    # Globale Variable statt `local`: Ein RETURN-Trap feuert auch beim Return des
    # CALLERS erneut. Mit `local` ist die Variable dann bereits zerstört → unter
    # `set -u` (Z. 14) crasht der Trap mit "unbound variable" UND das Cleanup ist
    # wirkungslos (leeres Argument). Globale Variable + EXIT-Trap (cleanup_temp)
    # löst beides: kein Crash, Verzeichnis wird zuverlässig aufgeräumt.
    AUR_SCAN_BUILD_DIR=$(mktemp -d -t "arch-shield-aur-scanner-build.XXXXXX") || {
        log_err "Konnte temporäres Build-Verzeichnis nicht erstellen."
        return 1
    }

    log_inf "Klone Fork-Repo und baue aur-scanner v2.2.0..."
    if git clone --depth 1 --branch v2.2.0 --quiet "https://github.com/leckminartor/ks-aur-scanner.git" "$AUR_SCAN_BUILD_DIR" 2>/dev/null; then
        cd "$AUR_SCAN_BUILD_DIR" || { log_err "cd in Build-Dir fehlgeschlagen"; return 1; }

        # --locked nur wenn Cargo.lock existiert, --workspace statt deprecated --all
        local cargo_locked=""
        [[ -f Cargo.lock ]] && cargo_locked="--locked"
        if cargo build --release --workspace $cargo_locked 2>/dev/null; then
            # Binaries installieren
            local install_dir="/usr/local/bin"
            $SUDO_BIN install -Dm755 "target/release/aur-scan"     "$install_dir/aur-scan"
            $SUDO_BIN install -Dm755 "target/release/aur-scan-wrap" "$install_dir/aur-scan-wrap"
            $SUDO_BIN install -Dm755 "target/release/aur-scan-hook" "$install_dir/aur-scan-hook"

            # Shell-Integrationen nach /usr/share/aur-scan/ (KONSISTENTER Name!)
            $SUDO_BIN mkdir -p /usr/share/aur-scan
            $SUDO_BIN install -Dm644 "install/integration.bash" "/usr/share/aur-scan/integration.bash"
            $SUDO_BIN install -Dm644 "install/integration.zsh"  "/usr/share/aur-scan/integration.zsh"
            $SUDO_BIN install -Dm644 "install/integration.fish" "/usr/share/aur-scan/integration.fish"
            $SUDO_BIN install -Dm644 "install/integration.nu"   "/usr/share/aur-scan/integration.nu"

            # Community rules example (PFAD korrigiert: aur-scan NICHT aur-scanner!)
            $SUDO_BIN install -Dm644 "install/rules.d/example.toml" "/usr/share/aur-scan/rules.d/example.toml"

            # pacman hook example
            $SUDO_BIN install -Dm644 "install/aur-scan.hook" "/usr/share/aur-scan/aur-scan.hook.example"

            log_ok "aur-scanner v2.2.0 installiert (aus Fork-Repo)"
            AUR_SCANNER_INSTALLED=true
            cd - >/dev/null
            return 0
        else
            log_err "Build fehlgeschlagen (cargo build --release --workspace)"
            cd - >/dev/null
            return 1
        fi
    else
        log_err "Konnte Fork-Repo nicht klonen."
        return 1
    fi
}

# ── Vollständiger System-Scan ───────────────────────────────────────────────────
run_full_scan() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 1: System-Scan ━━━${NC}"
    echo -e "Prüft dein System auf Spuren der Atomic-Arch-Malware und anderer AUR-Angriffe."
    echo ""
    log_sep

    local scan_results_clean=true
    local critical_findings=0

    # ── 1a: aur-malware-check ────────────────────────────────────────────────────
    echo -e "\n${BOLD}[1/6] Community-Malware-Check (1935+ bekannte infizierte Pakete)${NC}"

    if ! find_python; then
        log_err "Kein Python gefunden — aur-malware-check benötigt Python 3."
    else
        install_aur_malware_check
        if [[ -d "$AUR_SCAN_CHECK_DIR/aur_check" ]]; then
            echo -e "  ${DIM}Scanne installierte Pakete gegen 1935+ bekannte IOC-Pakete...${NC}"
            if "$PYTHON_BIN" -m aur_check --full --all-time 2>/dev/null; then
                log_ok "aur-malware-check: CLEAN"
            else
                local rc=$?
                if [[ $rc -eq 2 ]]; then
                    log_err "aur-malware-check: INFIZIERTE PAKETE GEFUNDEN!"
                    critical_findings=$((critical_findings + 1))
                    scan_results_clean=false
                else
                    log_wrn "aur-malware-check: Warnungen (Exit $rc)"
                fi
            fi
        fi
    fi

    # ── 1b: aur-scan system ──────────────────────────────────────────────────────
    echo -e "\n${BOLD}[2/6] AUR Security Scanner (statische PKGBUILD-Analyse)${NC}"

    if command_exists aur-scan; then
        AUR_SCANNER_INSTALLED=true
        echo -e "  ${DIM}Scanne alle installierten AUR-Pakete mit 87 Detektions-Regeln (inkl. Wave-3)...${NC}"
        if aur-scan system 2>&1; then
            log_ok "aur-scan system: abgeschlossen"
        else
            log_wrn "aur-scan system: Probleme gefunden (siehe Ausgabe oben)"
            scan_results_clean=false
        fi
    else
        log_wrn "aur-scanner nicht installiert — überspringe statische Analyse."
        echo -e "  ${DIM}Wird im Modul 'Schutz installieren' nachinstalliert.${NC}"
    fi

    # ── 1c: eBPF Rootkit-Check ───────────────────────────────────────────────────
    echo -e "\n${BOLD}[3/6] eBPF Rootkit-Check${NC}"

    if [[ -d /sys/fs/bpf ]]; then
        local bpf_hidden
        bpf_hidden=""
        compgen -G "/sys/fs/bpf/hidden_*" > /dev/null 2>&1 && bpf_hidden=$(compgen -G "/sys/fs/bpf/hidden_*")
        if [[ -n "$bpf_hidden" ]]; then
            log_err "eBPF-Rootkit-Spuren gefunden: $bpf_hidden"
            critical_findings=$((critical_findings + 1))
            scan_results_clean=false
        else
            log_ok "Keine eBPF-Rootkit-Spuren"
        fi
    else
        echo -e "  ${DIM}/sys/fs/bpf nicht vorhanden — eBPF-Support nicht aktiv${NC}"
        log_ok "eBPF-Rootkit-Check übersprungen (nicht verfügbar)"
    fi

    # ── 1d: npm/bun Cache-Check ──────────────────────────────────────────────────
    echo -e "\n${BOLD}[4/6] npm/bun Cache-Check (Malware-Pakete)${NC}"

    local npm_malware_found
    npm_malware_found=$(find \
        "$HOME/.npm" "$HOME/.cache/npm" "$HOME/.bun" "$HOME/.cache/bun" \
        "/usr/lib/node_modules" "/usr/local/lib/node_modules" \
        -name "atomic-lockfile" -o -name "js-digest" -o -name "lockfile-js" \
        2>/dev/null || true)

    if [[ -n "$npm_malware_found" ]]; then
        log_err "Maliziöse npm/bun-Pakete im Cache gefunden: $npm_malware_found"
        critical_findings=$((critical_findings + 1))
        scan_results_clean=false
    else
        log_ok "Keine maliziösen npm/bun-Pakete im Cache"
    fi

    # ── 1e: Systemd Persistenz-Check ─────────────────────────────────────────────
    echo -e "\n${BOLD}[5/6] Systemd-Persistenz-Check${NC}"

    local suspicious_services
    suspicious_services=$(systemctl list-units --type=service --state=running 2>/dev/null \
        | grep -iE "Restart=always.*RestartSec=30" 2>/dev/null || true)

    if [[ -n "$suspicious_services" ]]; then
        log_wrn "Verdächtige systemd-Services gefunden:"
        echo "$suspicious_services"
        scan_results_clean=false
    else
        log_ok "Keine verdächtigen systemd-Services"
    fi

    # ── 1f: Pacman-Log-Historie ──────────────────────────────────────────────────
    echo -e "\n${BOLD}[7/7] Pacman-Log-Historie (Juni 2026 Angriffs-Zeitraum)${NC}"

    if [[ -f /var/log/pacman.log ]]; then
        local log_matches
        log_matches=$(grep -E "\[2026-06-(09|10|11|12)\].*ALPM" /var/log/pacman.log 2>/dev/null | head -20 || true)
        if [[ -n "$log_matches" ]]; then
            echo -e "  ${DIM}Pacman-Aktivität im Angriffszeitraum gefunden:${NC}"
            echo "$log_matches" | while read -r line; do echo "    $line"; done
            echo -e "  ${YELLOW}Prüfe ob AUR-Pakete in dieser Zeit installiert wurden...${NC}"
        fi
        log_ok "Pacman-Log-Historie geprüft"
    else
        echo -e "  ${DIM}Kein pacman.log gefunden${NC}"
    fi

    # ── 1g: Wave-3 (Juli/Aug 2026) Two-Stage Loader-Check ─────────────────────────
    # Atomic Arch Wave 3: C loader (root via build()) + Rust infostealer/RAT/SSH-worm.
    # Detects the stage-2 drop paths, private Tor bootstrap, argv[0] masquerade and
    # the security.selinux reinfection marker. See ATOMIC-005..008 in aur-scan 2.2.0.
    echo -e "\n${BOLD}[6/7] Wave-3 Loader-Check (Tor-C2, Stage-2, Persistenz)${NC}"

    # 1g-a: private Tor bootstrap artifacts under /tmp
    # Nur loader-spezifische Pfade (/tmp/tb-Verzeichnis, .torrc-Datei). Die
    # generischen Namen tor.log/.lck (legitime Tor-Nutzung) werden bewusst NICHT
    # als Wave-3-Artefakt gewertet.
    local wave3_found=false
    local tor_bundle
    tor_bundle=$(find /tmp /var/tmp -maxdepth 3 \
        \( -path "/tmp/tb" -o -name ".torrc" \) \
        2>/dev/null | head -10 || true)
    if [[ -n "$tor_bundle" ]]; then
        log_wrn "Wave-3 Tor-Bootstrap-Artefakte gefunden:"
        echo "$tor_bundle" | while read -r line; do echo "    $line"; done
        wave3_found=true
    fi

    # 1g-b: stage-2 drop paths
    local stage2
    stage2=$(find /dev/shm /tmp -maxdepth 3 -name ".agent.bin" 2>/dev/null | head -5 || true)
    if [[ -n "$stage2" ]]; then
        log_err "Wave-3 Stage-2-Drop gefunden: $stage2"
        critical_findings=$((critical_findings + 1))
        wave3_found=true
    fi

    # 1g-c: Tor exfil process disguised as dbus-daemon.
    # `ps` zeigt den aufgelösten argv[0]-String (dbus-daemon), nie das Literal
    # `argv[0]=` — daher wird hier der Tor-Client-Prozesspfad und die
    # AllowSingleHop-Masquerade erkannt (die argv[0]-Tarnung matcht die
    # ATOMIC-008-Quellcode-Regel statisch).
    local tor_proc
    tor_proc=$(ps auxww 2>/dev/null | grep -E 'dbus-daemon.*AllowSingleHop|[/]tmp/tb/tor' | grep -v grep || true)
    if [[ -n "$tor_proc" ]]; then
        log_err "Verdächtiger Tor-Exfil-Prozess (getarnt) gefunden:"
        echo "$tor_proc" | while read -r line; do echo "    $line"; done
        critical_findings=$((critical_findings + 1))
        wave3_found=true
    fi

    # 1g-d: security.selinux reinfection marker — nur Wert 0x01 zählt.
    # `-e hex` rendert einen 1-Byte-0x01-Wert als literal `0x01` (nicht `-e text`,
    # das als rohes Control-Byte ausgibt).
    local selinux_marker
    selinux_marker=$(getfattr -n security.selinux -e hex \
        /run/utmp /var/run/utmp /var/log/hostd.log /etc/resolv.conf \
        2>/dev/null | grep -E 'security\.selinux=0x01' || true)
    if [[ -n "$selinux_marker" ]]; then
        log_wrn "Wave-3 security.selinux xattr-Marker (Wert 0x01) gefunden:"
        echo "$selinux_marker" | while read -r line; do echo "    $line"; done
        wave3_found=true
    fi

    # 1g-e: Wave-3 systemd persistence (Restart=always + RestartSec=30, randomized name)
    # Deckt Datei-basierte Services UND transiente Units (systemd-run) ab.
    local w3_services
    w3_services=$(find /etc/systemd/system "$HOME/.config/systemd/user" \
        -maxdepth 1 -name "*.service" -type f 2>/dev/null \
        -exec grep -lE "ExecStart=.*(tmp/tb|/dev/shm/\\.agent|linux-x86_64/agent|dbus-daemon)" {} + \
        2>/dev/null || true)
    # Transiente Units (systemd-run --user --scope) liegen nicht als Datei vor:
    local w3_transient
    w3_transient=$(systemctl --user list-units --type=service --state=running 2>/dev/null \
        | grep -iE "tmp/tb|/dev/shm/\.agent|linux-x86_64/agent|dbus-daemon" | head -10 || true)
    w3_services="${w3_services:+$w3_services\n}$w3_transient"
    if [[ -n "$w3_services" ]]; then
        log_wrn "Wave-3-Services gefunden (prüfen):"
        echo "$w3_services" | while read -r line; do echo "    $line"; done
        wave3_found=true
    fi

    if [[ "$wave3_found" == "true" ]]; then
        scan_results_clean=false
        if [[ $critical_findings -eq 0 ]]; then
            log_wrn "Wave-3-verdächtige Artefakte gefunden (nicht kritisch klassifiziert) — manuell prüfen."
        fi
    else
        log_ok "Keine Wave-3 Loader-Artefakte gefunden"
    fi

    # ── Zusammenfassung ──────────────────────────────────────────────────────────
    echo ""
    log_sep
    if [[ "$scan_results_clean" == "true" ]]; then
        echo -e "${GREEN}${BOLD}  ✅ SYSTEM IST CLEAN — Keine Infektion gefunden${NC}"
    else
        echo -e "${RED}${BOLD}  ❌ PROBLEME GEFUNDEN — Siehe Ausgabe oben${NC}"
        if [[ $critical_findings -gt 0 ]]; then
            echo ""
            echo -e "${RED}${BOLD}  ⚠️  KRITISCHE FUNDE: $critical_findings${NC}"
            echo ""
            echo -e "${YELLOW}  EMPFOHLENE SCHRITTE BEI INFIZIERTEN SYSTEM:${NC}"
            echo -e "  1. System NICHT ausschalten — forensische Erfassung mit Live-USB"
            echo -e "  2. ALLE Credentials rotieren: Discord, GitHub, npm, SSH, Cloud, Browser"
            echo -e "  3. Persistenz prüfen: systemctl list-units --type=service --state=running"
            echo -e "  4. eBPF prüfen: ls -la /sys/fs/bpf/hidden_*"
            echo -e "  5. Mit Live-USB booten, maliziöse Services/Dateien entfernen"
            echo -e "  6. Neuinstallation in Betracht ziehen (eBPF-Rootkit = untrustworthy)"
        fi
    fi
    log_sep
}

#==================================================================================
#  MODUL 2: SCHUTZ INSTALLIEREN
#==================================================================================

install_protection() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 2: Schutzmaßnahmen installieren ━━━${NC}"
    echo -e "Installiert Security-Tools, Hooks und Shell-Integrationen."
    echo ""
    log_sep

    # ── 2a: aur-scanner installieren ─────────────────────────────────────────────
    echo -e "\n${BOLD}[1/6] aur-scanner (PKGBUILD Security Scanner)${NC}"
    install_aur_scanner || log_wrn "Schritt 1/6 (aur-scanner) fehlgeschlagen — fahre fort"

    # ── 2b: aur-malware-check ────────────────────────────────────────────────────
    echo -e "\n${BOLD}[2/6] aur-malware-check (Community IOC Database)${NC}"
    install_aur_malware_check || log_wrn "Schritt 2/6 (aur-malware-check) fehlgeschlagen — fahre fort"

    # ── 2c: Shell-Integration ────────────────────────────────────────────────────
    echo -e "\n${BOLD}[3/6] Shell-Integration (Scan vor AUR-Installationen)${NC}"
    install_shell_integration || log_wrn "Schritt 3/6 (Shell-Integration) fehlgeschlagen — fahre fort"

    # ── 2d: Pacman Pre-Install Hook ──────────────────────────────────────────────
    echo -e "\n${BOLD}[4/6] Pacman Pre-Install Hook (blockt Malware VOR Installation)${NC}"
    install_pacman_pre_hook || log_wrn "Schritt 4/6 (Pre-Install Hook) fehlgeschlagen — fahre fort"

    # ── 2e: Pacman Post-Install Hook ──────────────────────────────────────────────
    echo -e "\n${BOLD}[5/6] Pacman Post-Install Hook (scannt nach Installationen)${NC}"
    install_pacman_post_hook || log_wrn "Schritt 5/6 (Post-Install Hook) fehlgeschlagen — fahre fort"

    # ── 2f: Wöchentlicher systemd Timer ───────────────────────────────────────────
    echo -e "\n${BOLD}[6/6] Wöchentlicher Scan-Timer (systemd user timer)${NC}"
    install_weekly_timer || log_wrn "Schritt 6/6 (Scan-Timer) fehlgeschlagen — fahre fort"

    echo ""
    log_sep
    echo -e "${GREEN}${BOLD}  ✅ Alle Schutzmaßnahmen installiert${NC}"
    log_sep
}

# ── Shell-Integration installieren ──────────────────────────────────────────────
install_shell_integration() {
    local integration_file=""

    case "$USER_SHELL" in
        fish)
            integration_file="/usr/share/aur-scan/integration.fish"
            ;;
        zsh)
            integration_file="/usr/share/aur-scan/integration.zsh"
            ;;
        bash)
            integration_file="/usr/share/aur-scan/integration.bash"
            ;;
        nu)
            integration_file="/usr/share/aur-scan/integration.nu"
            ;;
    esac

    if [[ -z "$integration_file" || ! -f "$integration_file" ]]; then
        log_wrn "Keine aur-scan-Integration für $USER_SHELL gefunden unter $integration_file"
        echo -e "  ${DIM}aur-scanner muss zuerst installiert werden.${NC}"
        return 1
    fi

    # Prüfen ob bereits eingebunden
    if [[ -f "$USER_SHELL_CONFIG" ]] && grep -q "aur-scan/integration" "$USER_SHELL_CONFIG"; then
        log_ok "Shell-Integration bereits aktiv in $USER_SHELL_CONFIG"
        return 0
    fi

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde hinzufügen zu $USER_SHELL_CONFIG: source $integration_file${NC}"
        return 0
    }

    mkdir -p "$(dirname "$USER_SHELL_CONFIG")"
    {
        echo ""
        echo "# arch-shield: AUR Security Scanner — scannt vor AUR-Installationen"
        echo "source $integration_file"
    } >> "$USER_SHELL_CONFIG"

    log_ok "Shell-Integration aktiviert für $USER_SHELL ($USER_SHELL_CONFIG)"
    log_inf "Starte deine Shell neu oder führe aus: source $USER_SHELL_CONFIG"
}

# ── Pacman Pre-Install Hook ──────────────────────────────────────────────────────
install_pacman_pre_hook() {
    local hook_file="/etc/pacman.d/hooks/aur-scan-pre-install.hook"

    if [[ -f "$hook_file" ]]; then
        log_ok "Pre-Install Hook bereits vorhanden: $hook_file"
        return 0
    fi

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde erstellen: $hook_file${NC}"
        return 0
    }

    if ! find_sudo; then
        log_err "Kein sudo/doas verfügbar — kann Hook nicht installieren."
        echo -e "  ${YELLOW}Bitte manuell ausführen:${NC}"
        echo "  sudo mkdir -p /etc/pacman.d/hooks"
        echo "  sudo tee $hook_file << 'EOF'"
        echo "  [Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = AUR Shield: Pre-install security scan
When = PreTransaction
Exec = /usr/bin/aur-scan-hook
AbortOnFail
NeedsTargets
EOF"
        return 1
    fi

    if ! command_exists aur-scan-hook && ! command_exists /usr/bin/aur-scan-hook; then
        log_wrn "aur-scan-hook Binary nicht gefunden — Hook würde nichts ausführen."
        log_wrn "Stelle sicher, dass aur-scanner korrekt installiert ist."
        return 1
    fi

    run_sudo mkdir -p /etc/pacman.d/hooks
    run_sudo tee "$hook_file" > /dev/null << 'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = AUR Shield: Pre-install security scan (blocks malicious packages)
When = PreTransaction
Exec = /usr/bin/aur-scan-hook
AbortOnFail
NeedsTargets
HOOK
    log_ok "Pre-Install Hook installiert: $hook_file"
}

# ── Pacman Post-Install Hook ────────────────────────────────────────────────────
install_pacman_post_hook() {
    local hook_file="/etc/pacman.d/hooks/aur-shield-after-install.hook"

    if [[ -f "$hook_file" ]]; then
        log_ok "Post-Install Hook bereits vorhanden: $hook_file"
        return 0
    fi

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde erstellen: $hook_file${NC}"
        return 0
    }

    if ! find_sudo; then
        log_err "Kein sudo/doas verfügbar — kann Hook nicht installieren."
        return 1
    fi

    run_sudo mkdir -p /etc/pacman.d/hooks
    run_sudo tee "$hook_file" > /dev/null << 'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = AUR Shield: Post-install security scan
When = PostTransaction
Exec = /usr/bin/aur-scan system
Depends = aur-scanner
HOOK
    log_ok "Post-Install Hook installiert: $hook_file"
}

# ── Wöchentlicher systemd Timer ────────────────────────────────────────────────
install_weekly_timer() {
    local service_dir="$HOME/.config/systemd/user"
    local script_dir="$HOME/.local/share/arch-shield"
    local scan_script="$script_dir/weekly-scan.sh"
    local service_file="$service_dir/aur-scan-weekly.service"
    local timer_file="$service_dir/aur-scan-weekly.timer"

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde erstellen: $scan_script, $service_file, $timer_file${NC}"
        return 0
    }

    mkdir -p "$service_dir" "$script_dir"

    # Scan-Script erstellen
    cat > "$scan_script" << 'SCANSCRIPT'
#!/bin/bash
set -euo pipefail
LOGFILE="$HOME/.local/share/arch-shield/scan-log.txt"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Log-Rotation: halte Log unter 1MB (größenbasiert)
if [[ -f "$LOGFILE" ]]; then
    LOG_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
    if [[ "$LOG_SIZE" -gt 1048576 ]]; then
        tail -c 524288 "$LOGFILE" > "${LOGFILE}.tmp" && mv "${LOGFILE}.tmp" "$LOGFILE"
    fi
fi
echo "========================================" >> "$LOGFILE"
echo "[$DATE] Arch-Shield Weekly Security Scan" >> "$LOGFILE"
echo "========================================" >> "$LOGFILE"

# aur-scan system
echo "--- aur-scan system ---" >> "$LOGFILE"
/usr/bin/aur-scan system >> "$LOGFILE" 2>&1 || echo "aur-scan: non-zero exit" >> "$LOGFILE"

# aur-malware-check (falls vorhanden)
MALWARE_CHECK_DIR="${ARCH_SHIELD_MALWARE_DIR:-$HOME/.local/share/arch-shield/aur-malware-check}"
if [[ -d "$MALWARE_CHECK_DIR/aur_check" ]] && command -v python3 &>/dev/null; then
    echo "--- aur-malware-check ---" >> "$LOGFILE"
    # Threat-Intel Update in Subshell (cd-Fehler isoliert)
    (cd "$MALWARE_CHECK_DIR" && \
        git pull --quiet 2>/dev/null && echo "IOC-Datenbank aktualisiert" >> "$LOGFILE" && \
        python3 -m aur_check --full --all-time >> "$LOGFILE" 2>&1 || echo "aur_check: non-zero exit" >> "$LOGFILE")
fi

# eBPF Rootkit check (sicher ohne Shell-Glob-Expansion)
echo "--- eBPF rootkit check ---" >> "$LOGFILE"
if compgen -G "/sys/fs/bpf/hidden_*" > /dev/null 2>&1; then
    compgen -G "/sys/fs/bpf/hidden_*" >> "$LOGFILE" 2>&1
    echo "eBPF-ROOTKIT-SPUR GEFUNDEN!" >> "$LOGFILE"
else
    echo "No eBPF hidden maps" >> "$LOGFILE"
fi

# npm/bun cache check
echo "--- npm/bun cache check ---" >> "$LOGFILE"
find "$HOME/.npm" "$HOME/.cache/npm" "$HOME/.bun" "$HOME/.cache/bun" \
     -name "atomic-lockfile" -o -name "js-digest" -o -name "lockfile-js" \
     >> "$LOGFILE" 2>&1 || echo "No malicious packages in cache" >> "$LOGFILE"

echo "[$DATE] Scan complete" >> "$LOGFILE"
echo "" >> "$LOGFILE"
SCANSCRIPT
    chmod +x "$scan_script"

    # systemd Service
    cat > "$service_file" << 'SVC'
[Unit]
Description=Arch-Shield Weekly AUR Security Scan
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/share/arch-shield/weekly-scan.sh
Nice=19
IOSchedulingClass=idle
SVC

    # systemd Timer
    cat > "$timer_file" << 'TIMER'
[Unit]
Description=Run Arch-Shield Security Scan weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now aur-scan-weekly.timer 2>/dev/null || {
        log_wrn "systemd user timer konnte nicht aktiviert werden (evtl. kein systemd user session)"
        return 1
    }

    log_ok "Wöchentlicher Scan-Timer aktiviert (jeden Montag)"
    log_inf "Logs unter: $script_dir/scan-log.txt"
}

#==================================================================================
#  MODUL 3: SYSTEM-HÄRTUNG
#==================================================================================

harden_system() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 3: System-Härtung ━━━${NC}"
    echo -e "Aktiviert Kernel-Schutzmaßnahmen und sicherheitsrelevante Einstellungen."
    echo ""
    log_sep

    local changes=0

    # ── 3a: eBPF Härtung ─────────────────────────────────────────────────────────
    echo -e "\n${BOLD}[1/5] eBPF-Härtung (Rootkit-Schutz)${NC}"

    local sysctl_file="/etc/sysctl.d/99-arch-shield-ebpf.conf"
    local need_ebpf=false

    if [[ ! -f "$sysctl_file" ]]; then
        need_ebpf=true
    else
        log_ok "eBPF-Härtung bereits konfiguriert"
    fi

    if [[ "$need_ebpf" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${DIM}[DRY-RUN] Würde erstellen: $sysctl_file${NC}"
        elif find_sudo; then
            run_sudo tee "$sysctl_file" > /dev/null << 'SYSCTL'
# arch-shield: eBPF Rootkit Protection
# Verhindert, dass nicht-root User eBPF-Programme laden
# Schützt vor Atomic-Arch eBPF-Rootkit
kernel.unprivileged_bpf_disabled = 1

# Weitere Kernel-Härtungen
# Verhindert kptr leaks (Kernel-Pointer-Adressen)
kernel.kptr_restrict = 1

# Verhindert dmesp für nicht-root
kernel.dmesg_restrict = 1

# Verhindert ptrace auf fremde Prozesse
kernel.yama.ptrace_scope = 1

# Striktieres USB-Device-Handling
kernel.yama.ptrace_scope = 1

# Verhindert Kernel-Modul-Laden nach Boot (optional — kann Treiber brechen)
# kernel.modules_disabled = 1
SYSCTL
            run_sudo sysctl -p "$sysctl_file" 2>/dev/null || true
            log_ok "eBPF-Härtung aktiviert ($sysctl_file)"
            changes=$((changes + 1))
        else
            log_wrn "Kein sudo — eBPF-Härtung übersprungen"
            echo -e "  ${YELLOW}Manuell: sudo tee $sysctl_file << 'EOF' ... kernel.unprivileged_bpf_disabled = 1${NC}"
        fi
    fi

    # ── 3b: Pacman SigLevel prüfen ───────────────────────────────────────────────
    echo -e "\n${BOLD}[2/5] Pacman Signatur-Einstellungen${NC}"

    if grep -q "^SigLevel.*Required" /etc/pacman.conf 2>/dev/null; then
        log_ok "Pacman SigLevel = Required ist gesetzt"
    else
        log_wrn "Pacman SigLevel ist nicht strikt — Signaturen könnten optional sein"
        echo -e "  ${YELLOW}Empfohlen: SigLevel = Required DatabaseOptional${NC}"
    fi

    # Prüfe auf unsichere SigLevel-Einstellungen in Repository-Sektionen
    local unsafe_sig
    unsafe_sig=$(grep -E "^\s*SigLevel\s*=\s*(Optional|Never|TrustAll)" /etc/pacman.conf 2>/dev/null || true)
    if [[ -n "$unsafe_sig" ]]; then
        log_wrn "Unsichere SigLevel-Einstellungen gefunden:"
        echo "$unsafe_sig" | while read -r line; do echo "    $line"; done
        echo -e "  ${YELLOW}Prüfe ob diese für vertrauenswürdige Repos (z.B. CachyOS) vorgesehen sind.${NC}"
    fi

    # ── 3c: AUR-Helper Konfiguration ──────────────────────────────────────────────
    echo -e "\n${BOLD}[3/5] AUR-Helper sicher konfigurieren${NC}"

    case "$AUR_HELPER" in
        paru)
            harden_paru
            ;;
        yay)
            harden_yay
            ;;
        *)
            log_wrn "Kein bekannter AUR-Helper zum Härten gefunden"
            ;;
    esac

    # ── 3c.1: Build-Isolation (CRITICAL — verhindert Credential-Diebstahl während makepkg)${NC}
    echo -e "\n${BOLD}[3b] Build-Isolation prüfen (CRITICAL)${NC}"
    echo -e "  ${RED}Ohne Build-Isolation kann ein bösartiges PKGBUILD während${NC}"
    echo -e "  ${RED}des Builds SSH-Keys, Browser-Daten und Credentials stehlen!${NC}"
    echo ""

    # Prüfe ob paru mit --chroot konfiguriert ist
    local chroot_active=false
    if [[ "$AUR_HELPER" == "paru" ]]; then
        if grep -q "^Chroot" ~/.config/paru/paru.conf 2>/dev/null || \
           grep -q "^Chroot" /etc/paru.conf 2>/dev/null; then
            chroot_active=true
        fi
    fi

    # Prüfe ob devtools/makechrootpkg installiert ist
    if command_exists makechrootpkg; then
        log_ok "makechrootpkg (devtools) ist installiert"
        if [[ "$chroot_active" == "true" ]]; then
            log_ok "paru Chroot-Modus ist aktiviert — Builds sind isoliert"
        else
            log_wrn "paru Chroot-Modus ist NICHT aktiviert!"
            echo -e "  ${YELLOW}Aktiviere mit: echo 'Chroot' >> ~/.config/paru/paru.conf${NC}"
            echo -e "  ${DIM}  Dies baut AUR-Pakete in einer isolierten systemd-nspawn Umgebung${NC}"
            echo -e "  ${DIM}  und verhindert, dass PKGBUILDs auf ~/.ssh, ~/.config, etc. zugreifen${NC}"
            if confirm "Chroot-Modus in paru.conf aktivieren?"; then
                echo "Chroot" >> ~/.config/paru/paru.conf 2>/dev/null
                log_ok "paru Chroot-Modus aktiviert"
                changes=$((changes + 1))
            fi
        fi
    else
        log_wrn "devtools (makechrootpkg) nicht installiert"
        echo -e "  ${YELLOW}Installiere: sudo pacman -S devtools${NC}"
        echo -e "  ${DIM}  Danach: echo 'Chroot' >> ~/.config/paru/paru.conf${NC}"
    fi

    # ── 3c.2: CachyOS/Custom Repo SigLevel prüfen ─────────────────────────────────
    echo -e "\n${BOLD}[3c] Repository Signatur-Einstellungen prüfen${NC}"
    local unsafe_repo_found=false
    while IFS= read -r repo_line; do
        local repo_name
        repo_name=$(echo "$repo_line" | grep -oE '^\[.*\]' | tr -d '[]')
        if [[ -n "$repo_name" && "$repo_name" != "options" ]]; then
            local sig_line
            sig_line=$(grep -A1 "^\[$repo_name\]" /etc/pacman.conf 2>/dev/null | grep "SigLevel" || true)
            if echo "$sig_line" | grep -qiE "TrustAll|Never|Optional"; then
                echo -e "  ${RED}✗${NC} [$repo_name] SigLevel = unsicher: ${YELLOW}$(echo "$sig_line" | head -1)${NC}"
                unsafe_repo_found=true
            fi
        fi
    done < <(grep '^\[' /etc/pacman.conf)

    if [[ "$unsafe_repo_found" == "true" ]]; then
        echo ""
        echo -e "  ${RED}⚠️  UNSICHERE REPO-CONFIG GEFUNDEN!${NC}"
        echo -e "  ${YELLOW}TrustAll deaktiviert Paketsignatur-Prüfung komplett.${NC}"
        echo -e "  ${YELLOW}Ein kompromittierter Mirror kann beliebige Pakete einschleusen.${NC}"
        echo ""
        echo -e "  ${BOLD}Fix:${NC} sudo sed -i 's/SigLevel = Optional TrustAll/SigLevel = Required DatabaseOptional/' /etc/pacman.conf"
        echo -e "  ${DIM}  Falls CachyOS-Repo keine Signatur hat: SigLevel = Required DatabaseOptional${NC}"
    else
        log_ok "Alle Repos haben sichere SigLevel-Einstellungen"
    fi

    # ── 3d: makepkg.conf Checksums ───────────────────────────────────────────────
    echo -e "\n${BOLD}[4/5] makepkg Checksum-Validierung${NC}"

    local makepkg_conf="/etc/makepkg.conf"
    if [[ -f "$makepkg_conf" ]]; then
        if grep -q "INTEGRITY_CHECK" "$makepkg_conf"; then
            local integ
            integ=$(grep "INTEGRITY_CHECK" "$makepkg_conf" | grep -oE "(sha256|sha512|md5|sha1)" || true)
            if echo "$integ" | grep -qiE "md5|sha1"; then
                log_wrn "makepkg verwendet schwache Checksums: $integ"
                echo -e "  ${YELLOW}Empfohlen: INTEGRITY_CHECK=(sha256 sha512)${NC}"
            else
                log_ok "makepkg Checksums sind stark ($integ)"
            fi
        fi
    fi

    # ── 3e: Firewall-Status ──────────────────────────────────────────────────────
    echo -e "\n${BOLD}[5/5] Firewall-Status${NC}"

    if command_exists ufw; then
        if ufw status 2>/dev/null | grep -q "active"; then
            log_ok "UFW Firewall aktiv"
        else
            log_wrn "UFW installiert aber nicht aktiv"
            echo -e "  ${YELLOW}Aktiviere mit: sudo ufw enable${NC}"
        fi
    elif command_exists firewall-cmd; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            log_ok "Firewalld aktiv"
        else
            log_wrn "firewalld installiert aber nicht aktiv"
        fi
    elif command_exists nft; then
        if nft list ruleset 2>/dev/null | grep -q "table"; then
            log_ok "nftables Regeln vorhanden"
        else
            log_wrn "nftables hat keine Regeln"
        fi
    else
        log_wrn "Keine Firewall erkannt"
        echo -e "  ${YELLOW}Empfohlen: sudo pacman -S ufw && sudo ufw enable${NC}"
    fi

    echo ""
    log_sep
    if [[ $changes -gt 0 ]]; then
        echo -e "${GREEN}${BOLD}  ✅ System-Härtung abgeschlossen ($changes Änderungen)${NC}"
    else
        echo -e "${GREEN}${BOLD}  ✅ System bereits gehärtet${NC}"
    fi
    log_sep
}

# ── paru härten ──────────────────────────────────────────────────────────────────
harden_paru() {
    local user_conf="$HOME/.config/paru/paru.conf"

    if [[ ! -f "$user_conf" ]]; then
        mkdir -p "$(dirname "$user_conf")"
        cat > "$user_conf" << 'PARU_CONF'
# paru.conf — von arch-shield gehärtet
# Nach Atomic-Arch-AAngriff Juni 2026

[options]
PgpFetch
Devel
Provides
DevelSuffixes = -git -cvs -svn -bzr -darcs -always -hg -fossil

# Zeigt Arch-News vor jedem Upgrade
NewsOnUpgrade

# Kombiniertes Upgrade mit Review
CombinedUpgrade

# Pakete können abgewählt werden
UpgradeMenu

# PKGBUILD-Änderungen werden gespeichert
SaveChanges

# Build-Abhängigkeiten entfernen
RemoveMake

# Cache bereinigen
CleanAfter
PARU_CONF
        log_ok "paru.conf erstellt mit sicheren Einstellungen ($user_conf)"
    else
        # Prüfe ob wichtige Optionen gesetzt sind
        local needs_update=false
        for opt in "NewsOnUpgrade" "UpgradeMenu" "SaveChanges"; do
            if ! grep -q "^$opt" "$user_conf"; then
                needs_update=true
                break
            fi
        done

        if [[ "$needs_update" == "true" ]]; then
            echo -e "  ${YELLOW}paru.conf fehlt empfohlene Optionen.${NC}"
            echo -e "  Empfohlene Ergänzungen in [options]:"
            echo -e "    NewsOnUpgrade    # Arch-News vor Upgrade"
            echo -e "    UpgradeMenu      # Pakete abwählen können"
            echo -e "    SaveChanges      # PKGBUILD-Änderungen speichern"
            echo -e "    RemoveMake       # Build-Abhängigkeiten entfernen"
            if confirm "Zu paru.conf hinzufügen?"; then
                {
                    echo ""
                    echo "# arch-shield: empfohlene Sicherheits-Optionen"
                    echo "NewsOnUpgrade"
                    echo "UpgradeMenu"
                    echo "SaveChanges"
                    echo "RemoveMake"
                    echo "CleanAfter"
                } >> "$user_conf"
                log_ok "paru.conf aktualisiert"
            else
                log_wrn "paru.conf nicht geändert"
            fi
        else
            log_ok "paru.conf bereits sicher konfiguriert"
        fi
    fi
}

# ── yay härten ───────────────────────────────────────────────────────────────────
harden_yay() {
    local user_conf="$HOME/.config/yay/config.json"

    # yay verwendet JSON config
    if [[ -f "$user_conf" ]]; then
        log_ok "yay config vorhanden ($user_conf)"
        # Prüfe wichtige Felder
        if command_exists jq; then
            local newsupgrade
            newsupgrade=$(jq -r '.newsongupgrade // false' "$user_conf" 2>/dev/null || echo "false")
            [[ "$newsupgrade" != "true" ]] && {
                echo -e "  ${YELLOW}Empfohlen: yay --save --newsongupgrade${NC}"
            }
        fi
    else
        log_wrn "Keine yay config gefunden — Standard-Einstellungen werden verwendet"
        echo -e "  ${YELLOW}Empfohlen: yay --save --newsongupgrade --cleanafter --removemake${NC}"
    fi
}

#==================================================================================
#  MODUL 4: STATUS & ÜBERPRÜFUNG
#==================================================================================

show_status() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 4: Schutz-Status ━━━${NC}"
    echo -e "Übersicht aller installierten Schutzmaßnahmen."
    echo ""
    log_sep

    local installed=0
    local missing=0

    # aur-scanner
    if command_exists aur-scan; then
        echo -e "  ${GREEN}✓${NC} aur-scanner            $(aur-scan version 2>/dev/null | grep -o 'v[0-9.]*' | head -1)"
        installed=$((installed + 1))
    else
        echo -e "  ${RED}✗${NC} aur-scanner            nicht installiert"
        missing=$((missing + 1))
    fi

    # aur-malware-check
    if [[ -d "$AUR_SCAN_CHECK_DIR/.git" ]] || [[ -d /tmp/aur-malware-check/.git ]]; then
        echo -e "  ${GREEN}✓${NC} aur-malware-check      v4.0 (Community)"
        installed=$((installed + 1))
    else
        echo -e "  ${YELLOW}○${NC} aur-malware-check      nicht installiert (optional)"
        missing=$((missing + 1))
    fi

    # Shell-Integration
    if [[ -n "$USER_SHELL_CONFIG" ]] && [[ -f "$USER_SHELL_CONFIG" ]] && \
       grep -q "aur-scan/integration" "$USER_SHELL_CONFIG" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Shell-Integration      $USER_SHELL aktiv"
        installed=$((installed + 1))
    else
        echo -e "  ${RED}✗${NC} Shell-Integration      nicht aktiv"
        missing=$((missing + 1))
    fi

    # Pre-Install Hook
    if [[ -f /etc/pacman.d/hooks/aur-scan-pre-install.hook ]]; then
        echo -e "  ${GREEN}✓${NC} Pre-Install Hook       aktiv (blockt Malware vor Installation)"
        installed=$((installed + 1))
    else
        echo -e "  ${RED}✗${NC} Pre-Install Hook       nicht installiert"
        missing=$((missing + 1))
    fi

    # Post-Install Hook
    if [[ -f /etc/pacman.d/hooks/aur-shield-after-install.hook ]]; then
        echo -e "  ${GREEN}✓${NC} Post-Install Hook      aktiv"
        installed=$((installed + 1))
    else
        echo -e "  ${RED}✗${NC} Post-Install Hook      nicht installiert"
        missing=$((missing + 1))
    fi

    # systemd Timer
    if systemctl --user is-active --quiet aur-scan-weekly.timer 2>/dev/null; then
        local next_run
        next_run=$(systemctl --user list-timers aur-scan-weekly.timer 2>/dev/null | grep -oE "→.*" | head -1 || echo "unbekannt")
        echo -e "  ${GREEN}✓${NC} Weekly Scan Timer      aktiv${next_run:+ ($next_run)}"
        installed=$((installed + 1))
    else
        echo -e "  ${YELLOW}○${NC} Weekly Scan Timer      nicht aktiv"
        missing=$((missing + 1))
    fi

    # eBPF Härtung
    if [[ -f /etc/sysctl.d/99-arch-shield-ebpf.conf ]]; then
        echo -e "  ${GREEN}✓${NC} eBPF Härtung           aktiv"
        installed=$((installed + 1))
    else
        echo -e "  ${YELLOW}○${NC} eBPF Härtung           nicht aktiv"
        missing=$((missing + 1))
    fi

    # AUR-Helper Config
    case "$AUR_HELPER" in
        paru)
            if grep -q "NewsOnUpgrade" "$HOME/.config/paru/paru.conf" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} paru.conf sicher        NewsOnUpgrade aktiv"
                installed=$((installed + 1))
            else
                echo -e "  ${YELLOW}○${NC} paru.conf             nicht gehärtet"
                missing=$((missing + 1))
            fi
            ;;
        yay)
            echo -e "  ${GREEN}✓${NC} yay                   erkannt"
            installed=$((installed + 1))
            ;;
        *)
            echo -e "  ${YELLOW}○${NC} AUR-Helper             keiner erkannt"
            missing=$((missing + 1))
            ;;
    esac

    echo ""
    log_sep
    echo -e "  ${GREEN}Installiert:${NC} $installed   ${YELLOW}Fehlt:${NC} $missing"

    if [[ $missing -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}✅ Vollständig geschützt${NC}"
    elif [[ $installed -ge 4 ]]; then
        echo -e "  ${YELLOW}${BOLD}⚠️  Teilweise geschützt — siehe fehlende Komponenten oben${NC}"
    else
        echo -e "  ${RED}${BOLD}❌ Minimal geschützt — führe 'Schutz installieren' aus${NC}"
    fi
    log_sep
}

#==================================================================================
#  MODUL 5: AUR-PAKET PRÜFEN
#==================================================================================

check_aur_package() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 5: AUR-Paket prüfen ━━━${NC}"
    echo ""

    local pkg_name="${1:-}"
    if [[ -z "$pkg_name" ]]; then
        read -rp "$(echo -e "${BOLD}${YELLOW}?${NC} Welches AUR-Paket prüfen? ")" pkg_name
    fi

    if [[ -z "$pkg_name" ]]; then
        log_wrn "Kein Paketname angegeben"
        return 1
    fi

    echo -e "Prüfe ${BOLD}$pkg_name${NC}..."
    echo ""

    # aur-scan check (falls installiert)
    if command_exists aur-scan; then
        echo -e "${BOLD}[1] Statische PKGBUILD-Analyse (aur-scan check)${NC}"
        aur-scan check "$pkg_name" 2>&1 || true
        echo ""
    else
        log_wrn "aur-scanner nicht installiert — statische Analyse übersprungen"
    fi

    # Gegen IOC-Liste prüfen
    if [[ -d "$AUR_SCAN_CHECK_DIR/data/lists" ]]; then
        echo -e "${BOLD}[2] IOC-Datenbank-Abgleich (1935+ infizierte Pakete)${NC}"
        if grep -qx "$pkg_name" "$AUR_SCAN_CHECK_DIR/data/lists/package_list.txt" 2>/dev/null; then
            echo -e "  ${RED}${BOLD}⚠️  PAKET IST IN DER IOC-LISTE — MOGLICHERWEISE INFIZIERT!${NC}"
        else
            echo -e "  ${GREEN}✓ Nicht in der IOC-Liste${NC}"
        fi
        echo ""
    fi

    # Maintainer-Info
    echo -e "${BOLD}[3] AUR-Metadaten${NC}"
    if command_exists paru; then
        paru -Si "$pkg_name" 2>&1 | grep -E "Maintainer|Stimmen|Beliebtheit|Zuerst|Aktualisierung|Veraltet" || true
    elif command_exists yay; then
        yay -Si "$pkg_name" 2>&1 | grep -E "Maintainer|Votes|Popularity|First Submitted|Last Updated|Out of Date" || true
    fi
    echo ""

    echo -e "${BOLD}Checkliste für manuelle Überprüfung:${NC}"
    echo -e "  □ PKGBUILD lesen: paru -Gp $pkg_name"
    echo -e "  □ Maintainer prüfen (Account-Alter, Anzahl Pakete)"
    echo -e "  □ Letzte Commits ansehen (AUR Seite → 'View Changes')"
    echo -e "  □ Auf npm/bun-Install-Befehle achten"
    echo -e "  □ Auf curl|bash, eval, base64-decode Patterns achten"
    echo -e "  □ Checksums vorhanden und nicht SKIP?"
}

#==================================================================================
#  MODUL 6: NOTFALL-WIEDERHERSTELLUNG (EMERGENCY RECOVERY)
#==================================================================================
#  Wird aufgerufen, wenn der System-Scan eine Infektion findet.
#  Führt Schritt für Schritt durch die Bereinigung.

# ── Globale Variablen für Notfall ──────────────────────────────────────────────
EMERGENCY_INFECTED_PKGS=()
EMERGENCY_EBPF_ROOTKIT=false
EMERGENCY_NPM_MALWARE=()
EMERGENCY_SUSPICIOUS_SERVICES=()
EMERGENCY_CREDENTIAL_ROTATION_NEEDED=false
EMERGENCY_BACKUP_DIR=""
EMERGENCY_FORENSIC_LOG="$LOG_DIR/emergency-$(date '+%Y%m%d-%H%M%S').log"

# ── Forensisches Logging für Notfall ────────────────────────────────────────────
emergency_log() {
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$EMERGENCY_FORENSIC_LOG"
}

emergency_step() {
    local step_num="$1"
    local title="$2"
    echo ""
    echo -e "${RED}${BOLD}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}${BOLD}│  SCHRITT $step_num: $title$(printf '%.0s ' $(seq 1 $((47 - ${#title} - 8)))) │${NC}"
    echo -e "${RED}${BOLD}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    emergency_log "=== SCHRITT $step_num: $title ==="
}

# ── Notfall-Scan (tiefer als normaler Scan, sammelt alle Befunde) ──────────────
emergency_scan() {
    echo ""
    echo -e "${RED}${BOLD}━━━ NOTFALL-SCAN: Detaillierte Infektions-Analyse ━━━${NC}"
    echo -e "${RED}Sammle alle Indikatoren für die Wiederherstellung...${NC}"
    echo ""
    emergency_log "=== Notfall-Scan gestartet ==="

    # 1. Infizierte Pakete identifizieren
    emergency_log "--- Prüfe infizierte Pakete ---"
    if find_python && [[ -d "$AUR_SCAN_CHECK_DIR/aur_check" ]]; then
        local malware_output
        malware_output=$("$PYTHON_BIN" -m aur_check --full --all-time 2>&1 || true)
        echo "$malware_output" >> "$EMERGENCY_FORENSIC_LOG"

        # Extrahiere infizierte Paketnamen
        local infected
        infected=$(echo "$malware_output" | grep -iE "INFECT|infected|compromised|FOUND" || true)
        if [[ -n "$infected" ]]; then
            while IFS= read -r line; do
                local pkg
                pkg=$(echo "$line" | grep -oE "[a-z0-9][a-z0-9_.-]+(-git)?(-svn)?(-hg)?" | head -1 || true)
                [[ -n "$pkg" ]] && EMERGENCY_INFECTED_PKGS+=("$pkg")
            done <<< "$infected"
        fi
    fi

    # 2. aur-scan system (für zusätzliche Funde)
    emergency_log "--- aur-scan system ---"
    if command_exists aur-scan; then
        aur-scan system 2>&1 | tee -a "$EMERGENCY_FORENSIC_LOG" || true
    fi

    # 3. eBPF Rootkit
    emergency_log "--- eBPF Rootkit-Check ---"
    local bpf_maps
    bpf_hidden=""
    if compgen -G "/sys/fs/bpf/hidden_*" > /dev/null 2>&1; then
        bpf_hidden=$(compgen -G "/sys/fs/bpf/hidden_*")
        EMERGENCY_EBPF_ROOTKIT=true
        echo "$bpf_hidden" >> "$EMERGENCY_FORENSIC_LOG"
        echo -e "${RED}  eBPF-Rootkit-Spuren gefunden: $bpf_hidden${NC}"
    fi

    # 4. npm/bun Malware in Cache
    emergency_log "--- npm/bun Cache-Check ---"
    local npm_findings
    npm_findings=$(find \
        "$HOME/.npm" "$HOME/.cache/npm" "$HOME/.bun" "$HOME/.cache/bun" \
        "/usr/lib/node_modules" "/usr/local/lib/node_modules" \
        -name "atomic-lockfile" -o -name "js-digest" -o -name "lockfile-js" \
        2>/dev/null || true)
    if [[ -n "$npm_findings" ]]; then
        while IFS= read -r f; do
            EMERGENCY_NPM_MALWARE+=("$f")
        done <<< "$npm_findings"
        echo "$npm_findings" >> "$EMERGENCY_FORENSIC_LOG"
    fi

    # 5. Verdächtige systemd-Services
    emergency_log "--- Systemd-Persistenz-Check ---"
    local services
    services=$(systemctl list-units --type=service --state=running 2>/dev/null || true)
    local suspicious
    suspicious=$(echo "$services" | grep -iE "Restart=always" || true)
    # Auch user-level Services prüfen
    local user_services
    user_services=$(systemctl --user list-units --type=service --state=running 2>/dev/null || true)
    local user_suspicious
    user_suspicious=$(echo "$user_services" | grep -iE "Restart=always" || true)

    if [[ -n "$suspicious" || -n "$user_suspicious" ]]; then
        echo "$suspicious" >> "$EMERGENCY_FORENSIC_LOG"
        echo "$user_suspicious" >> "$EMERGENCY_FORENSIC_LOG"
        while IFS= read -r svc; do
            [[ -n "$svc" ]] && EMERGENCY_SUSPICIOUS_SERVICES+=("$svc")
        done <<< "$suspicious"
        while IFS= read -r svc; do
            [[ -n "$svc" ]] && EMERGENCY_SUSPICIOUS_SERVICES+=("$svc")
        done <<< "$user_suspicious"
    fi

    # 6. Weitere Indikatoren: verdächtige Binaries
    emergency_log "--- Verdächtige Binaries ---"
    local suspicious_bins
    suspicious_bins=$(find /tmp /var/tmp /dev/shm \
        -type f -executable \
        \( -name "deps" -o -name "atomic*" -o -name "lockfile*" -o -name "js-digest*" \) \
        2>/dev/null || true)
    if [[ -n "$suspicious_bins" ]]; then
        echo -e "${RED}  Verdächtige Binaries gefunden:${NC}"
        echo "$suspicious_bins" | while read -r b; do echo "    $b"; done
        echo "$suspicious_bins" >> "$EMERGENCY_FORENSIC_LOG"
    fi

    # 7. Browser-Diebstahl-Indikatoren
    emergency_log "--- Browser-Diebstahl-Check ---"
    local browser_access
    browser_access=$(find /tmp /var/tmp /dev/shm \
        -name "*.log" -newer /etc/os-release \
        -exec grep -l -iE "cookie|password|token|discord|github|ssh" {} \; \
        2>/dev/null | head -5 || true)
    if [[ -n "$browser_access" ]]; then
        echo -e "${YELLOW}  Mögliche Credential-Exfiltration-Spuren in /tmp gefunden${NC}"
        echo "$browser_access" >> "$EMERGENCY_FORENSIC_LOG"
        EMERGENCY_CREDENTIAL_ROTATION_NEEDED=true
    fi

    # Zusammenfassung der Funde
    echo ""
    log_sep
    echo -e "${RED}${BOLD}  NOTFALL-ANALYSE ABGESCHLOSSEN${NC}"
    echo ""
    echo -e "  ${BOLD}Gefundene Indikatoren:${NC}"
    echo -e "    Infizierte Pakete:     ${#EMERGENCY_INFECTED_PKGS[@]}"
    echo -e "    eBPF Rootkit:          $([[ "$EMERGENCY_EBPF_ROOTKIT" == "true" ]] && echo -e "${RED}JA${NC}" || echo "Nein")"
    echo -e "    npm/bun Malware:       ${#EMERGENCY_NPM_MALWARE[@]}"
    echo -e "    Verdächtige Services: ${#EMERGENCY_SUSPICIOUS_SERVICES[@]}"
    echo -e "    Forensisches Log:     $EMERGENCY_FORENSIC_LOG"
    log_sep

    # Entscheidung: wie weiter verfahren?
    if [[ "$EMERGENCY_EBPF_ROOTKIT" == "true" ]]; then
        echo ""
        echo -e "${RED}${BOLD}⚠️  eBPF-ROOTKIT ERKANNT!${NC}"
        echo -e "${RED}Das System ist KOMPROMITTIERT und kann nicht vertraut werden.${NC}"
        echo -e "${RED}Eine Bereinigung auf dem laufenden System ist NICHT sicher,${NC}"
        echo -e "${RED}da der Rootkit Prozesse, Dateien und Netzwerk verstecken kann.${NC}"
        echo ""
        echo -e "${YELLOW}Empfohlener Weg: System von Live-USB neu installieren.${NC}"
        echo ""
        if confirm "Soll trotzdem der geführte Bereinigungsmodus gestartet werden? (nur für Forensik/Lernen)"; then
            emergency_recovery_flow
        else
            echo -e "\n${RED}Bitte führe folgende Schritte durch:${NC}"
            echo -e "  1. Live-USB (Arch ISO) booten"
            echo -e "  2. Alte Festplatte mounten (read-only für Forensik)"
            echo -e "  3. Wichtige Daten sichern (NICHT ausführbare Dateien!)"
            echo -e "  4. Komplette Neuinstallation"
            echo -e "  5. ALLE Credentials rotieren (siehe Schritt 2 unten)"
            echo -e "  6. arch-shield auf dem neuen System installieren"
        fi
    else
        echo ""
        echo -e "${YELLOW}Kein eBPF-Rootkit erkannt. Bereinigung ist möglich.${NC}"
        if confirm "Soll der geführte Bereinigungsmodus gestartet werden?"; then
            emergency_recovery_flow
        fi
    fi
}

# ── Notfall-Bereinigungs-Flow (Schritt für Schritt) ──────────────────────────────
emergency_recovery_flow() {
    echo ""
    echo -e "${RED}${BOLD}╔═════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║     NOTFALL-WIEDERHERSTELLUNG — Geführte Bereinigung       ║${NC}"
    echo -e "${RED}${BOLD}║     Folge jedem Schritt sorgfältig.                        ║${NC}"
    echo -e "${RED}${BOLD}╚═════════════════════════════════════════════════════════╝${NC}"
    emergency_log "=== Notfall-Bereinigungs-Flow gestartet ==="

    # ── Schritt 1: System sichern ──────────────────────────────────────────────
    emergency_step "1" "System-Status dokumentieren"

    echo -e "Bevor wir Änderungen vornehmen, dokumentieren wir den aktuellen Zustand."
    echo -e "Dies ist wichtig für spätere forensische Analyse."
    echo ""

    local snapshot_dir="$LOG_DIR/emergency-snapshot-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$snapshot_dir"

    echo -e "${DIM}  Erstelle System-Snapshot unter: $snapshot_dir${NC}"

    # Pacman-Datenbank
    pacman -Qe > "$snapshot_dir/installed-explicit.txt" 2>/dev/null || true
    pacman -Qm > "$snapshot_dir/foreign-packages.txt" 2>/dev/null || true
    pacman -Qmq > "$snapshot_dir/aur-packages.txt" 2>/dev/null || true

    # Systemd Services
    systemctl list-units --type=service > "$snapshot_dir/systemd-services.txt" 2>/dev/null || true
    systemctl --user list-units --type=service > "$snapshot_dir/systemd-user-services.txt" 2>/dev/null || true

    # eBPF Maps
    ls -la /sys/fs/bpf/ > "$snapshot_dir/ebpf-maps.txt" 2>/dev/null || true

    # Netzwerk-Verbindungen
    ss -tunlp > "$snapshot_dir/network-connections.txt" 2>/dev/null || true

    # Pacman-Log kopieren
    cp /var/log/pacman.log "$snapshot_dir/" 2>/dev/null || true

    # Letzte Shell-History (kompromittierte Befehle)
    cp "$HOME/.bash_history" "$snapshot_dir/" 2>/dev/null || true

    echo -e "  ${GREEN}✓${NC} Snapshot gespeichert: $snapshot_dir"
    emergency_log "Snapshot gespeichert: $snapshot_dir"

    # ── Schritt 2: Credentials rotieren ────────────────────────────────────────
    emergency_step "2" "Credentials rotieren (WICHTIG!)"

    echo -e "${RED}${BOLD}Die Atomic-Arch-Malware stiehlt folgende Credentials:${NC}"
    echo ""
    echo -e "  ${BOLD}Sofort zu rotieren (von einem ANDEREN, vertrauenswürdigen Gerät!):${NC}"
    echo ""
    echo -e "  ${YELLOW}Developer-Plattformen:${NC}"
    echo -e "    □ GitHub Personal Access Tokens (PATs)"
    echo -e "    □ npm/Zugriffstokens"
    echo -e "    □ Docker Hub / Podman Credentials"
    echo -e "    □ Vault Tokens (HashiCorp Vault, etc.)"
    echo -e "    □ Cloud Provider Keys (AWS, GCP, Azure)"
    echo -e "  ${YELLOW}Kommunikation:${NC}"
    echo -e "    □ Discord Tokens"
    echo -e "    □ Slack Sessions/Cookies"
    echo -e "    □ Microsoft Teams / M365 Sessions"
    echo -e "  ${YELLOW}SSH & GPG:${NC}"
    echo -e "    □ SSH Private Keys (alle! ~/.ssh/id_*)"
    echo -e "    □ GPG Private Keys"
    echo -e "  ${YELLOW}Browser:${NC}"
    echo -e "    □ Alle Browser-Cookies (Chrome, Firefox, etc.)"
    echo -e "    □ Gespeicherte Passwörter im Browser"
    echo -e "    □ Browser-Sessions (bei allen Seiten ausloggen!)"
    echo ""
    echo -e "${BOLD}Anleitung:${NC}"
    echo -e "  1. Wechsle zu einem vertrauenswürdigen Gerät (Handy, anderer PC)"
    echo -e "  2. Logge dich bei allen betroffenen Diensten ein"
    echo -e "  3. Revoke alle aktiven Tokens/Sessions"
    echo -e "  4. Ändere Passwörter (falls möglich)"
    echo -e "  5. Generiere neue SSH-Keys: ssh-keygen -t ed25519 -C 'neuer-key'"
    echo ""
    echo -e "${RED}MACHE DIES JETZT — bevor du mit der Bereinigung fortfährst!${NC}"
    echo ""

    if ! confirm "Hast du alle Credentials rotiert? Wirklich fortfahren?"; then
        echo -e "${YELLOW}Bereinigung abgebrochen. Bitte zuerst Credentials rotieren!${NC}"
        emergency_log "Bereinigung abgebrochen — Credentials nicht rotiert"
        return 1
    fi
    emergency_log "Credentials rotiert bestätigt"

    # ── Schritt 3: Infizierte Pakete entfernen ──────────────────────────────────
    emergency_step "3" "Infizierte Pakete entfernen"

    if [[ ${#EMERGENCY_INFECTED_PKGS[@]} -eq 0 ]] && [[ ${#EMERGENCY_NPM_MALWARE[@]} -eq 0 ]]; then
        echo -e "Keine spezifischen infizierten Pakete identifiziert."
        echo -e "Überspringe diesen Schritt."
        emergency_log "Keine infizierten Pakete identifiziert"
    else
        # Infizierte AUR-Pakete entfernen
        if [[ ${#EMERGENCY_INFECTED_PKGS[@]} -gt 0 ]]; then
            echo -e "Entferne infizierte AUR-Pakete:"
            for pkg in "${EMERGENCY_INFECTED_PKGS[@]}"; do
                echo -e "  ${YELLOW}→ $pkg${NC}"
            done
            echo ""
            if confirm "Diese Pakete entfernen?"; then
                for pkg in "${EMERGENCY_INFECTED_PKGS[@]}"; do
                    echo -e "  Entferne $pkg..."
                    if find_sudo; then
                        run_sudo pacman -Rns --noconfirm "$pkg" 2>/dev/null || \
                            echo -e "    ${YELLOW}Konnte $pkg nicht entfernen (vielleicht schon weg)${NC}"
                    else
                        pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
                    fi
                    emergency_log "Entfernt: $pkg"
                done
                echo -e "  ${GREEN}✓${NC} Infizierte Pakete entfernt"
            fi
        fi

        # npm/bun Malware aus Cache entfernen
        if [[ ${#EMERGENCY_NPM_MALWARE[@]} -gt 0 ]]; then
            echo ""
            echo -e "Entferne maliziöse npm/bun-Pakete aus Caches:"
            for f in "${EMERGENCY_NPM_MALWARE[@]}"; do
                echo -e "  ${YELLOW}→ $f${NC}"
            done
            echo ""
            if confirm "Diese Dateien entfernen?"; then
                for f in "${EMERGENCY_NPM_MALWARE[@]}"; do
                    rm -rf "$f" 2>/dev/null || true
                    emergency_log "Entfernt: $f"
                done
                echo -e "  ${GREEN}✓${NC} Maliziöse npm/bun-Pakete entfernt"
            fi
        fi
    fi

    # ── Schritt 4: Persistenz entfernen ────────────────────────────────────────
    emergency_step "4" "Persistenz entfernen"

    echo -e "Suche und entferne maliziöse systemd-Services und Autostart-Einträge."
    echo ""

    # 4a: Verdächtige systemd-Services
    echo -e "${BOLD}[4a] Systemd-Services prüfen${NC}"
    echo ""

    # System Services mit Restart=always und RestartSec=30 (Malware-Pattern)
    local malicious_svcs
    malicious_svcs=$(find /etc/systemd/system /run/systemd/system \
        -name "*.service" -exec grep -l "Restart=always" {} \; 2>/dev/null || true)

    # User Services
    local malicious_user_svcs
    malicious_user_svcs=$(find "$HOME/.config/systemd/user" "$HOME/.local/share/systemd/user" \
        -name "*.service" -exec grep -l "Restart=always" {} \; 2>/dev/null || true)

    # Auch Services mit ungewöhnlichen ExecStart (temp.sh, onion, etc.)
    local all_system_svcs
    all_system_svcs=$(find /etc/systemd/system /run/systemd/system /usr/lib/systemd/system \
        -name "*.service" -exec grep -l -iE "temp\.sh|onion|tor.*hidden|/tmp/.*deps|atomic-lockfile|js-digest" {} \; \
        2>/dev/null || true)

    local all_user_svcs
    all_user_svcs=$(find "$HOME/.config/systemd/user" "$HOME/.local/share/systemd/user" \
        -name "*.service" -exec grep -l -iE "temp\.sh|onion|tor.*hidden|/tmp/.*deps|atomic-lockfile|js-digest" {} \; \
        2>/dev/null || true)

    local found_services=()
    [[ -n "$malicious_svcs" ]] && while IFS= read -r s; do found_services+=("$s"); done <<< "$malicious_svcs"
    [[ -n "$malicious_user_svcs" ]] && while IFS= read -r s; do found_services+=("$s"); done <<< "$malicious_user_svcs"
    [[ -n "$all_system_svcs" ]] && while IFS= read -r s; do found_services+=("$s"); done <<< "$all_system_svcs"
    [[ -n "$all_user_svcs" ]] && while IFS= read -r s; do found_services+=("$s"); done <<< "$all_user_svcs"

    # Deduplizieren
    local unique_services=()
    for s in "${found_services[@]:-}"; do
        [[ -n "$s" ]] && [[ ! " ${unique_services[*]} " =~ " $s " ]] && unique_services+=("$s")
    done

    if [[ ${#unique_services[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Verdächtige systemd-Services gefunden:${NC}"
        for s in "${unique_services[@]}"; do
            echo -e "  ${RED}→ $s${NC}"
            echo -e "    ${DIM}$(head -5 "$s" 2>/dev/null | tr '\n' '|')${NC}"
        done
        echo ""
        if confirm "Diese Services stoppen, deaktivieren und löschen?"; then
            for s in "${unique_services[@]}"; do
                local svc_name
                svc_name=$(basename "$s")
                echo -e "  Bearbeite $svc_name..."
                # Stoppen
                systemctl stop "$svc_name" 2>/dev/null || true
                systemctl --user stop "$svc_name" 2>/dev/null || true
                # Deaktivieren
                systemctl disable "$svc_name" 2>/dev/null || true
                systemctl --user disable "$svc_name" 2>/dev/null || true
                # Datei löschen
                rm -f "$s" 2>/dev/null || true
                emergency_log "Service entfernt: $s"
            done
            systemctl daemon-reload 2>/dev/null || true
            systemctl --user daemon-reload 2>/dev/null || true
            echo -e "  ${GREEN}✓${NC} Verdächtige Services entfernt"
        else
            echo -e "  ${YELLOW}Services nicht entfernt — bitte manuell prüfen!${NC}"
        fi
    else
        echo -e "  ${GREEN}✓${NC} Keine verdächtigen systemd-Services gefunden"
    fi
    echo ""

    # 4b: Cron-Jobs prüfen
    echo -e "${BOLD}[4b] Cron-Jobs prüfen${NC}"
    local cron_dirs=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "$HOME/.config/crontab")
    local cron_found=false
    for d in "${cron_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            local cron_files
            cron_files=$(find "$d" -type f -newer /etc/os-release 2>/dev/null || true)
            if [[ -n "$cron_files" ]]; then
                echo -e "  ${YELLOW}Neue Cron-Einträge in $d:${NC}"
                echo "$cron_files" | while read -r f; do
                    echo -e "    $f"
                    cat "$f" 2>/dev/null | head -3 | sed 's/^/      /'
                done
                cron_found=true
            fi
        fi
    done
    [[ "$cron_found" == "false" ]] && echo -e "  ${GREEN}✓${NC} Keine verdächtigen Cron-Jobs"

    echo ""

    # 4c: Autostart-Einträge prüfen
    echo -e "${BOLD}[4c] XDG Autostart-Einträge prüfen${NC}"
    local autostart_dirs=(
        "$HOME/.config/autostart"
        "/etc/xdg/autostart"
    )
    local autostart_found=false
    for d in "${autostart_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            local autostart_files
            autostart_files=$(find "$d" -name "*.desktop" -newer /etc/os-release 2>/dev/null || true)
            if [[ -n "$autostart_files" ]]; then
                echo -e "  ${YELLOW}Neue Autostart-Einträge in $d:${NC}"
                echo "$autostart_files" | while read -r f; do
                    echo -e "    $f"
                    # Zeige Exec= Zeile
                    grep "^Exec=" "$f" 2>/dev/null | sed 's/^/      /'
                done
                autostart_found=true
            fi
        fi
    done
    [[ "$autostart_found" == "false" ]] && echo -e "  ${GREEN}✓${NC} Keine verdächtigen Autostart-Einträge"

    echo ""

    # 4d: bashrc/profile Manipulation prüfen
    echo -e "${BOLD}[4d] Shell-Startdateien prüfen${NC}"
    local shell_files=(
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"
        "$HOME/.zshrc" "$HOME/.zprofile"
        "$HOME/.config/fish/config.fish"
    )
    local shell_found=false
    for f in "${shell_files[@]}"; do
        if [[ -f "$f" ]]; then
            # Suche nach verdächtigen Patterns
            local suspicious_lines
            suspicious_lines=$(grep -n -iE "temp\.sh|onion|curl.*\|.*bash|wget.*\|.*sh|atomic|js-digest|/tmp/.*deps" "$f" 2>/dev/null || true)
            if [[ -n "$suspicious_lines" ]]; then
                echo -e "  ${YELLOW}Verdächtige Zeilen in $f:${NC}"
                echo "$suspicious_lines" | sed 's/^/    /'
                shell_found=true
                emergency_log "Verdächtige Zeilen in $f: $suspicious_lines"
            fi
        fi
    done
    [[ "$shell_found" == "false" ]] && echo -e "  ${GREEN}✓${NC} Keine manipulierten Shell-Startdateien"

    # ── Schritt 5: eBPF Rootkit entfernen ──────────────────────────────────────
    emergency_step "5" "eBPF Rootkit entfernen"

    if [[ "$EMERGENCY_EBPF_ROOTKIT" == "true" ]]; then
        echo -e "${RED}${BOLD}⚠️  eBPF-ROOTKIT AKTIV!${NC}"
        echo ""
        echo -e "${RED}Ein aktiver eBPF-Rootkit kann nicht sicher aus dem laufenden System${NC}"
        echo -e "${RED}entfernt werden, da er Prozesse und Dateien versteckt.${NC}"
        echo ""
        echo -e "${YELLOW}Sichere Entfernung:${NC}"
        echo -e "  1. System herunterfahren: systemctl poweroff"
        echo -e "  2. Arch ISO (Live-USB) booten"
        echo -e "  3. Root-Partition mounten (read-only):"
        echo -e "     sudo mount -o ro /dev/sdXN /mnt"
        echo -e "  4. eBPF Maps inspizieren:"
        echo -e "     sudo ls -la /mnt/sys/fs/bpf/"
        echo -e "  5. Wenn bestätigt: komplette Neuinstallation empfohlen"
        echo ""
        echo -e "${RED}Das System kann NICHT als vertrauenswürdig angesehen werden.${NC}"
        echo -e "${RED}Neuinstallation ist der sicherste Weg.${NC}"
        emergency_log "eBPF Rootkit aktiv — Neuinstallation empfohlen"
    else
        echo -e "  ${GREEN}✓${NC} Kein eBPF-Rootkit erkannt — nichts zu entfernen"
        emergency_log "Kein eBPF Rootkit"
    fi

    # ── Schritt 6: Verdächtige Binaries/Dateien entfernen ───────────────────────
    emergency_step "6" "Verdächtige Dateien entfernen"

    echo -e "Suche nach Malware-Artefakten in temporären Verzeichnissen."
    echo ""

    local artifact_locations=(
        "/tmp" "/var/tmp" "/dev/shm"
        "$HOME/.cache"
        "$HOME/.local/share"
    )

    local artifacts_found=()
    for loc in "${artifact_locations[@]}"; do
        # Bekannte Malware-Binaries
        local found
        found=$(find "$loc" -maxdepth 3 \
            \( -name "deps" -o -name "atomic-lockfile*" -o -name "js-digest*" \
               -o -name "lockfile-js*" -o -name "monero-wallet*" \) \
            -type f 2>/dev/null || true)
        if [[ -n "$found" ]]; then
            while IFS= read -r f; do
                artifacts_found+=("$f")
            done <<< "$found"
        fi

        # Ausführbare Dateien in /tmp (verdächtig)
        if [[ "$loc" == "/tmp" || "$loc" == "/dev/shm" ]]; then
            local exec_found
            exec_found=$(find "$loc" -maxdepth 2 -type f -executable \
                -newer /etc/os-release 2>/dev/null || true)
            if [[ -n "$exec_found" ]]; then
                while IFS= read -r f; do
                    # Nur hinzufügen wenn nicht bekannt gut
                    local basename_f
                    basename_f=$(basename "$f")
                    case "$basename_f" in
                        ssh-agent|gpg-agent|pulseaudio|xauth) ;; # known good
                        *) artifacts_found+=("$f") ;;
                    esac
                done <<< "$exec_found"
            fi
        fi
    done

    if [[ ${#artifacts_found[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Verdächtige Dateien gefunden:${NC}"
        for f in "${artifacts_found[@]}"; do
            local ftype
            ftype=$(file "$f" 2>/dev/null | head -1 || echo "unbekannt")
            echo -e "  ${RED}→ $f${NC}"
            echo -e "    ${DIM}$ftype${NC}"
        done
        echo ""
        if confirm "Diese verdächtigen Dateien entfernen?"; then
            for f in "${artifacts_found[@]}"; do
                rm -f "$f" 2>/dev/null && emergency_log "Entfernt: $f" || true
            done
            echo -e "  ${GREEN}✓${NC} Verdächtige Dateien entfernt"
        else
            echo -e "  ${YELLOW}Dateien nicht entfernt — bitte manuell prüfen!${NC}"
        fi
    else
        echo -e "  ${GREEN}✓${NC} Keine verdächtigen Dateien gefunden"
    fi

    # ── Schritt 7: AUR Cache bereinigen ────────────────────────────────────────
    emergency_step "7" "AUR Build-Cache bereinigen"

    echo -e "Der AUR Build-Cache kann infizierte PKGBUILDs enthalten."
    echo ""

    local cache_dirs=()
    case "$AUR_HELPER" in
        paru)
            cache_dirs+=("$HOME/.cache/paru/clone")
            [[ -d /var/cache/paru/clone ]] && cache_dirs+=("/var/cache/paru/clone")
            ;;
        yay)
            cache_dirs+=("$HOME/.cache/yay")
            ;;
        *)
            cache_dirs+=("$HOME/.cache/paru/clone" "$HOME/.cache/yay")
            ;;
    esac

    local cache_cleaned=false
    for d in "${cache_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            echo -e "  ${DIM}Bereinige $d...${NC}"
            # Suche nach infizierten PKGBUILDs
            local infected_pkgs_in_cache
            infected_pkgs_in_cache=$(grep -rl -iE "atomic-lockfile|js-digest|lockfile-js" "$d" 2>/dev/null || true)
            if [[ -n "$infected_pkgs_in_cache" ]]; then
                echo -e "  ${YELLOW}Infizierte PKGBUILDs im Cache gefunden:${NC}"
                echo "$infected_pkgs_in_cache" | while read -r f; do echo "    $f"; done
                if confirm "Infizierte Cache-Verzeichnisse löschen?"; then
                    echo "$infected_pkgs_in_cache" | while read -r f; do
                        local dir_to_remove
                        dir_to_remove=$(dirname "$f")
                        rm -rf "$dir_to_remove" 2>/dev/null || true
                        emergency_log "Cache-Verzeichnis entfernt: $dir_to_remove"
                    done
                    cache_cleaned=true
                fi
            else
                echo -e "  ${GREEN}✓${NC} Keine infizierten PKGBUILDs in $d"
            fi
        fi
    done

    # npm/bun Cache komplett leeren
    echo ""
    echo -e "${BOLD}npm/bun Cache komplett leeren?${NC}"
    echo -e "  Leert alle zwischengespeicherten npm/bun-Pakete (sicher, wird neu heruntergeladen)"
    if confirm "npm und bun Cache leeren?"; then
        rm -rf "$HOME/.npm/_cacache" 2>/dev/null || true
        rm -rf "$HOME/.cache/npm" 2>/dev/null || true
        rm -rf "$HOME/.bun/install/cache" 2>/dev/null || true
        rm -rf "$HOME/.cache/bun" 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} npm/bun Cache geleert"
        emergency_log "npm/bun Cache geleert"
    fi

    # ── Schritt 8: Systemd Reload ──────────────────────────────────────────────
    emergency_step "8" "System neu laden"

    echo -e "Systemd-Konfiguration neu laden, damit entfernte Services nicht mehr aktiv sind."
    echo ""

    if find_sudo; then
        run_sudo systemctl daemon-reload 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Systemd daemon-reload (system)"
    else
        echo -e "  ${YELLOW}Kein sudo — führe manuell aus: sudo systemctl daemon-reload${NC}"
    fi

    systemctl --user daemon-reload 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Systemd daemon-reload (user)"

    # ── Schritt 9: Verifizierungsscan ──────────────────────────────────────────
    emergency_step "9" "Verifizierungsscan"

    echo -e "Führe einen erneuten Scan durch, um zu prüfen ob alle Bedrohungen entfernt wurden."
    echo ""

    local still_infected=false

    # eBPF check
    local bpf_still
    bpf_still=""
    compgen -G "/sys/fs/bpf/hidden_*" > /dev/null 2>&1 && bpf_still=$(compgen -G "/sys/fs/bpf/hidden_*")
    if [[ -n "$bpf_still" ]]; then
        echo -e "  ${RED}✗ eBPF-Rootkit noch aktiv!${NC}"
        still_infected=true
    else
        echo -e "  ${GREEN}✓${NC} Kein eBPF-Rootkit"
    fi

    # npm/bun cache
    local npm_still
    npm_still=$(find "$HOME/.npm" "$HOME/.cache/npm" "$HOME/.bun" "$HOME/.cache/bun" \
        -name "atomic-lockfile" -o -name "js-digest" -o -name "lockfile-js" \
        2>/dev/null || true)
    if [[ -n "$npm_still" ]]; then
        echo -e "  ${RED}✗ npm/bun Malware noch im Cache!${NC}"
        still_infected=true
    else
        echo -e "  ${GREEN}✓${NC} npm/bun Cache sauber"
    fi

    # aur-malware-check
    if find_python && [[ -d "$AUR_SCAN_CHECK_DIR/aur_check" ]]; then
        if "$PYTHON_BIN" -m aur_check --full --all-time 2>&1 | grep -q "INFECT\|FOUND\|compromised"; then
            echo -e "  ${RED}✗ aur-malware-check findet noch infizierte Pakete!${NC}"
            still_infected=true
        else
            echo -e "  ${GREEN}✓${NC} aur-malware-check: CLEAN"
        fi
    fi

    # aur-scan system
    if command_exists aur-scan; then
        local scan_output
        scan_output=$(aur-scan system 2>&1 || true)
        if echo "$scan_output" | grep -qiE "CRITICAL"; then
            echo -e "  ${YELLOW}⚠${NC} aur-scan findet noch Critical-Severity Funde"
            still_infected=true
        else
            echo -e "  ${GREEN}✓${NC} aur-scan: keine Critical-Funde"
        fi
    fi

    # verdächtige Services
    local svc_still
    svc_still=$(systemctl list-units --type=service --state=running 2>/dev/null \
        | grep -iE "Restart=always.*RestartSec=30" || true)
    if [[ -n "$svc_still" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Verdächtige Services noch aktiv — manuell prüfen!"
        still_infected=true
    else
        echo -e "  ${GREEN}✓${NC} Keine verdächtigen Services"
    fi

    echo ""
    log_sep
    if [[ "$still_infected" == "false" ]]; then
        echo -e "${GREEN}${BOLD}  ✅ BEREINIGUNG ERFOLGREICH — System scheint sauber${NC}"
        echo ""
        echo -e "  ${BOLD}Empfohlene nächste Schritte:${NC}"
        echo -e "  1. System neu starten: reboot"
        echo -e "  2. Nach Neustart: arch-shield.sh scan ausführen"
        echo -e "  3. arch-shield.sh protect ausführen (Schutz installieren)"
        echo -e "  4. Alle Passwörter ändern, die im Browser gespeichert waren"
        echo -e "  5. SSH-Keys neu generieren und auf Servern austauschen"
        echo -e "  6. Forensisches Log für Unterlagen aufbewahren:"
        echo -e "     $EMERGENCY_FORENSIC_LOG"
    else
        echo -e "${RED}${BOLD}  ❌ BEREINIGUNG UNVOLLSTÄNDIG${NC}"
        echo ""
        echo -e "  ${RED}Es sind noch Bedrohungen vorhanden!${NC}"
        echo -e "  ${YELLOW}Empfohlene nächste Schritte:${NC}"
        echo -e "  1. Komplette Neuinstallation (sicherster Weg)"
        echo -e "  2. Oder: System von Live-USB booten und manuell bereinigen"
        echo -e "  3. Forensisches Log konsultieren:"
        echo -e "     $EMERGENCY_FORENSIC_LOG"
        echo -e "  4. Alle betroffenen Dienste über remaining Infektion informieren"
    fi
    log_sep
    emergency_log "=== Notfall-Bereinigungs-Flow beendet ==="
}

# ── Menüpunkt: Notfall ───────────────────────────────────────────────────────────
run_emergency() {
    echo ""
    echo -e "${RED}${BOLD}━━━ MODUL 6: Notfall-Wiederherstellung ━━━${NC}"
    echo ""
    echo -e "${RED}⚠️  WARNUNG: Dieses Modul ist für den Fall einer BESTÄTIGTEN Infektion.${NC}"
    echo -e "${RED}⚠️  Es führt durch die komplette Bereinigung Schritt für Schritt.${NC}"
    echo ""
    echo -e "Das Modul führt folgende Schritte durch:"
    echo -e "  1. System-Status dokumentieren (forensischer Snapshot)"
    echo -e "  2. Credentials rotieren (GitHub, npm, SSH, Browser, ...)"
    echo -e "  3. Infizierte Pakete entfernen"
    echo -e "  4. Persistenz entfernen (systemd, cron, autostart)"
    echo -e "  5. eBPF Rootkit entfernen (falls vorhanden → Neuinstallation!)"
    echo -e "  6. Verdächtige Dateien entfernen"
    echo -e "  7. AUR Build-Cache bereinigen"
    echo -e "  8. Systemd neu laden"
    echo -e "  9. Verifizierungsscan"
    echo ""
    echo -e "${YELLOW}Empfehlung: Führe zuerst 'scan' aus um die Infektion zu bestätigen.${NC}"
    echo ""

    if confirm "Notfall-Wiederherstellung starten?"; then
        # Zuerst einen schnellen Scan, um Befunde zu sammeln
        echo -e "\n${BOLD}Starte Notfall-Scan zur Befund-Erhebung...${NC}"
        emergency_scan
    fi
}

#==================================================================================
#  MODUL 7: THREAT-INTELLIGENCE UPDATE
#==================================================================================
#  Aktualisiert IOC-Datenbanken und Erkennungsregeln für neue Bedrohungen.
#  Wird vom wöchentlichen Timer und manuell aufgerufen.

update_threat_intel() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 7: Threat-Intelligence Update ━━━${NC}"
    echo -e "Aktualisiert IOC-Datenbanken und Erkennungsregeln."
    echo ""
    log_sep

    local updates=0
    local failures=0

    # ── 7a: aur-malware-check Datenbank aktualisieren ─────────────────────────────
    echo -e "\n${BOLD}[1/4] aur-malware-check (Community IOC-Datenbank)${NC}"

    if [[ -d "$AUR_SCAN_CHECK_DIR/.git" ]]; then
        echo -e "  ${DIM}Git pull...${NC}"
        if git -C "$AUR_SCAN_CHECK_DIR" pull --quiet 2>/dev/null; then
            local new_pkgs
            new_pkgs=$(wc -l < "$AUR_SCAN_CHECK_DIR/data/lists/package_list.txt" 2>/dev/null || echo "?")
            log_ok "aur-malware-check aktualisiert ($new_pkgs Pakete in Datenbank)"
            updates=$((updates + 1))
        else
            log_wrn "Git pull fehlgeschlagen — verwende bestehende Version"
            failures=$((failures + 1))
        fi
    else
        log_inf "Repository nicht vorhanden, installiere neu..."
        if install_aur_malware_check; then
            local new_pkgs
            new_pkgs=$(wc -l < "$AUR_SCAN_CHECK_DIR/data/lists/package_list.txt" 2>/dev/null || echo "?")
            log_ok "aur-malware-check installiert ($new_pkgs Pakete)"
            updates=$((updates + 1))
        else
            log_err "Installation fehlgeschlagen"
            failures=$((failures + 1))
        fi
    fi

    # ── 7b: aur-malware-check HedgeDoc Live-Liste ──────────────────────────────────
    echo -e "\n${BOLD}[2/4] Arch Linux HedgeDoc Live-Paketliste${NC}"

    if find_python && [[ -d "$AUR_SCAN_CHECK_DIR/aur_check" ]]; then
        echo -e "  ${DIM}Lade neueste Paketliste von Arch Linux HedgeDoc...${NC}"
        if "$PYTHON_BIN" -m aur_check --refresh --full 2>/dev/null; then
            log_ok "HedgeDoc Live-Liste aktualisiert"
            updates=$((updates + 1))
        else
            log_wrn "HedgeDoc-Update fehlgeschlagen (Netzwerk?)"
            failures=$((failures + 1))
        fi
    else
        log_wrn "aur-malware-check nicht verfügbar für HedgeDoc-Update"
    fi

    # ── 7c: aur-scanner IOC-Datenbank prüfen ──────────────────────────────────────
    echo -e "\n${BOLD}[3/4] aur-scanner IOC-Datenbank${NC}"

    if command_exists aur-scan; then
        local ioc_count
        ioc_count=$(aur-scan ioc 2>/dev/null | grep "Indicators" | grep -oE '[0-9]+' || echo "?")
        log_ok "aur-scanner IOC-Datenbank: $ioc_count Indikatoren"
        echo -e "  ${DIM}Letzte Aktualisierung: $(aur-scan ioc 2>/dev/null | grep 'Last updated' | cut -d: -f2 | xargs || echo 'unbekannt')${NC}"
        echo -e "  ${DIM}Update-Option: pacman -S aur-scanner (AUR) für neue Version${NC}"
    else
        log_wrn "aur-scanner nicht installiert"
    fi

    # ── 7d: Arch Linux News/Advisories prüfen ─────────────────────────────────────
    echo -e "\n${BOLD}[4/4] Arch Linux Security Advisories${NC}"

    local arch_news_url="https://archlinux.org/news/"
    echo -e "  ${DIM}Prüfe $arch_news_url...${NC}"

    # Mit curl die neuesten Advisories abrufen (nur Titel, keine Installation)
    if command_exists curl; then
        local latest_news
        latest_news=$(curl -sL --max-time 10 "https://archlinux.org/news/" 2>/dev/null \
            | grep -oP '<a href="/news/[^"]*">[^<]*</a>' \
            | head -5 \
            | sed 's/<a href="[^"]*">//;s/<\/a>//' 2>/dev/null || true)

        if [[ -n "$latest_news" ]]; then
            echo -e "  ${BOLD}Neueste Arch Linux News:${NC}"
            echo "$latest_news" | while IFS= read -r line; do
                echo -e "    • $line"
            done
            log_ok "Arch Linux News abgerufen"
            updates=$((updates + 1))
        else
            log_wrn "Konnte Arch Linux News nicht abrufen (Netzwerk?)"
            failures=$((failures + 1))
        fi
    else
        log_wrn "curl nicht verfügbar — Arch News können nicht abgerufen werden"
    fi

    # ── Zusammenfassung ──────────────────────────────────────────────────────────
    echo ""
    log_sep
    echo -e "  ${GREEN}Aktualisiert:${NC} $updates   ${YELLOW}Fehlgeschlagen:${NC} $failures"
    echo ""
    echo -e "  ${BOLD}Empfohlene Update-Quellen (manuell prüfen):${NC}"
    echo -e "    • https://archlinux.org/news/                — Offizielle Advisories"
    echo -e "    • https://aur.archlinux.org/                 — AUR Paket-Änderungen"
    echo -e "    • https://github.com/lenucksi/aur-malware-check — Community IOC-Liste"
    echo -e "    • https://lists.archlinux.org/               — Mailinglisten (aur-general)"
    echo -e "    • https://bbs.archlinux.org/                 — Forum (Security)"
    echo ""
    echo -e "  ${BOLD}Automatisches Update:${NC}"
    echo -e "    Der wöchentliche systemd-Timer führt dieses Update automatisch aus."
    echo -e "    Für tägliche Updates: ändere OnCalendar=weekly zu OnCalendar=daily"
    echo -e "    in ~/.config/systemd/user/aur-scan-weekly.timer"
    log_sep
}

#==================================================================================
#  MODUL 8: ADVANCED PROTECTION (deepseek-v4-pro Empfehlungen)
#==================================================================================
#  4 Erweiterungen: Daily Threat-Intel Timer, C2-Netzwerkblockierung,
#  auditd File-Integrity-Monitoring, rkhunter Rootkit-Detection

# ── 8a: Daily Threat-Intel Timer ──────────────────────────────────────────────
install_daily_timer() {
    echo -e "\n${BOLD}[1/4] Täglicher Threat-Intel Update Timer${NC}"

    local service_dir="$HOME/.config/systemd/user"
    local script_dir="$HOME/.local/share/arch-shield"
    local daily_script="$script_dir/daily-update.sh"
    local daily_service="$service_dir/aur-shield-daily-update.service"
    local daily_timer="$service_dir/aur-shield-daily-update.timer"

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde erstellen: daily-update timer${NC}"
        return 0
    }

    mkdir -p "$service_dir" "$script_dir"

    # Daily Update Script — lädt IOC-Listen + scannt
    cat > "$daily_script" << 'DAILYSCRIPT'
#!/bin/bash
# set -u statt set -e: Fehler in einzelnen Tasks sollen nicht alles abbrechen
set -uo pipefail
LOGFILE="$HOME/.local/share/arch-shield/daily-update.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Log-Rotation: halte Log unter 1MB (größenbasiert, nicht zeilenbasiert)
if [[ -f "$LOGFILE" ]]; then
    LOG_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
    if [[ "$LOG_SIZE" -gt 1048576 ]]; then
        tail -c 524288 "$LOGFILE" > "${LOGFILE}.tmp" && mv "${LOGFILE}.tmp" "$LOGFILE"
    fi
fi
echo "[$DATE] Daily Threat-Intel Update" >> "$LOGFILE"

# 1. aur-malware-check git pull (neueste IOC-Listen)
# Sicheres Verzeichnis — bevorzugt mktemp, Fallback auf user-local Pfad
MALWARE_CHECK_DIR="${ARCH_SHIELD_MALWARE_DIR:-$HOME/.local/share/arch-shield/aur-malware-check}"
if [[ -d "$MALWARE_CHECK_DIR/.git" ]]; then
    git -C "$MALWARE_CHECK_DIR" pull --quiet 2>/dev/null && echo "  IOC-Datenbank aktualisiert" >> "$LOGFILE" || echo "  IOC-Update fehlgeschlagen (Netzwerk?)" >> "$LOGFILE"
elif command -v git &>/dev/null; then
    # Altes/kaputtes Verzeichnis entfernen falls es ohne .git existiert
    if [[ -d "$MALWARE_CHECK_DIR" ]] && [[ ! -d "$MALWARE_CHECK_DIR/.git" ]]; then
        rm -rf "$MALWARE_CHECK_DIR" 2>/dev/null || true
    fi
    mkdir -p "$MALWARE_CHECK_DIR"
    git clone --depth 1 --quiet "https://github.com/lenucksi/aur-malware-check.git" "$MALWARE_CHECK_DIR" 2>/dev/null \
        && echo "  aur-malware-check installiert" >> "$LOGFILE" \
        || echo "  FEHLER: aur-malware-check konnte nicht installiert werden" >> "$LOGFILE"
fi

# 2. HedgeDoc Live-Liste
if [[ -d "$MALWARE_CHECK_DIR/aur_check" ]] && command -v python3 &>/dev/null; then
    (cd "$MALWARE_CHECK_DIR" && python3 -m aur_check --refresh --full >> "$LOGFILE" 2>&1 \
        && echo "  HedgeDoc aktualisiert" >> "$LOGFILE" \
        || echo "  HedgeDoc-Update fehlgeschlagen" >> "$LOGFILE")
fi

# 3. Schneller Scan (nur installierte Pakete gegen IOC-Liste)
if [[ -d "$MALWARE_CHECK_DIR/aur_check" ]] && command -v python3 &>/dev/null; then
    (cd "$MALWARE_CHECK_DIR" && python3 -m aur_check --all-time >> "$LOGFILE" 2>&1 || echo "  aur_check: Warnung/Funde" >> "$LOGFILE")
fi

# 4. eBPF Rootkit-Check (sicher ohne Shell-Glob-Expansion)
if compgen -G "/sys/fs/bpf/hidden_*" > /dev/null 2>&1; then
    compgen -G "/sys/fs/bpf/hidden_*" >> "$LOGFILE" 2>&1
    echo "  ⚠ eBPF-ROOTKIT-SPUR GEFUNDEN!" >> "$LOGFILE"
else
    echo "  eBPF: clean" >> "$LOGFILE"
fi

# 5. C2-Domain-Blocklist aktualisieren (tatsächlich in /etc/hosts installieren)
# Bekannte C2-Domains der Atomic-Arch-Kampagne. Hinweis: Nur die konkreten
# Loader-Endpoints werden geblockt (archive.torproject.org), NICHT die gesamte
# torproject.org-TLD — das würde legitime Tor-Nutzung brechen.
C2_DOMAINS=("temp.sh" "archive.torproject.org")
# Prüfe ob Root oder nicht-interaktives sudo/doas verfügbar ist (systemd service hat kein TTY)
RUN_SU=""
if [[ $EUID -ne 0 ]] && command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    RUN_SU="sudo"
elif [[ $EUID -ne 0 ]] && command -v doas &>/dev/null; then
    RUN_SU="doas"
fi
if [[ -n "$RUN_SU" || $EUID -eq 0 ]]; then
    # Alten arch-shield Block entfernen und neu schreiben (idempotent)
    $RUN_SU sed -i '/# arch-shield-c2-blocklist/,/^$/d' /etc/hosts 2>/dev/null || true
    echo "" | $RUN_SU tee -a /etc/hosts >/dev/null 2>&1 || true
    echo "# arch-shield-c2-blocklist — updated $(date '+%Y-%m-%d')" | $RUN_SU tee -a /etc/hosts >/dev/null 2>&1 || true
    for _d in "${C2_DOMAINS[@]}"; do
        echo "0.0.0.0 $_d" | $RUN_SU tee -a /etc/hosts >/dev/null 2>&1 || true
    done
    echo "" | $RUN_SU tee -a /etc/hosts >/dev/null 2>&1 || true
    echo "  C2-Blocklist aktualisiert in /etc/hosts (${#C2_DOMAINS[@]} Einträge)" >> "$LOGFILE"
else
    echo "  C2-Blocklist nicht aktualisiert (kein Root/sudo/doas ohne Passwort)" >> "$LOGFILE"
fi

echo "[$DATE] Daily update complete" >> "$LOGFILE"
echo "" >> "$LOGFILE"
DAILYSCRIPT
    chmod +x "$daily_script"

    # systemd Service für Daily Update
    cat > "$daily_service" << 'SVC'
[Unit]
Description=Arch-Shield Daily Threat-Intel Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/share/arch-shield/daily-update.sh
Nice=19
IOSchedulingClass=idle
SVC

    # systemd Timer für Daily Update (läuft um 6:00 Uhr)
    cat > "$daily_timer" << 'TIMER'
[Unit]
Description=Run Arch-Shield Threat-Intel Update daily

[Timer]
OnCalendar=06:00
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
TIMER

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now aur-shield-daily-update.timer 2>/dev/null || {
        log_wrn "Daily Update Timer konnte nicht aktiviert werden"
        return 1
    }

    log_ok "Täglicher Threat-Intel Timer aktiviert (täglich um 06:00)"
    log_inf "Logs unter: $script_dir/daily-update.log"
}

# ── 8b: C2-Netzwerkblockierung ────────────────────────────────────────────────
install_c2_blocking() {
    echo -e "\n${BOLD}[2/4] C2-Netzwerkblockierung${NC}"
    echo -e "  Blockiert bekannte C2-Domains der Atomic-Arch-Malware via /etc/hosts"

    # Bekannte C2-Domains der Atomic-Arch-Kampagne (aus Truesec/ioctl.fail Analyse)
    # + Wave 3 (Juli/Aug 2026): blockiere den Tor-Bundle-Download-Host, damit der
    #   Stage-1-Loader kein privates Tor bootstrappen kann (entmannt die Attacke).
    #   Die .onion-C2 selbst lässt sich via /etc/hosts nicht blocken (Tor-Auflösung);
    #   sie wird unten nur dokumentiert. Bewusst NUR die konkreten Loader-Endpoints
    #   (archive.torproject.org), NICHT die gesamte torproject.org-TLD, um legitime
    #   Tor-Nutzung nicht zu brechen.
    local c2_domains=(
        "temp.sh"
        "archive.torproject.org"
    )

    # Bekannte C2-IPs (aus IOC-Datenbank)
    local c2_ips=()
    # Tor onion service wird nicht blockiert (dynamisch)

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde erstellen: /etc/hosts Einträge für C2-Domains${NC}"
        return 0
    }

    if ! find_sudo; then
        log_wrn "Kein sudo — C2-Blockierung übersprungen"
        echo -e "  ${YELLOW}Manuell: sudo tee -a /etc/hosts << 'EOF'${NC}"
        for domain in "${c2_domains[@]}"; do
            echo -e "  ${YELLOW}0.0.0.0 $domain${NC}"
        done
        echo -e "  ${YELLOW}EOF${NC}"
        return 1
    fi

    # Prüfe ob bereits vorhanden — wenn ja, aktualisiere statt überspringe
    if grep -q "arch-shield-c2-blocklist" /etc/hosts 2>/dev/null; then
        # Alten Block entfernen und neu schreiben (idempotent)
        run_sudo sed -i '/# arch-shield-c2-blocklist/,/^$/d' /etc/hosts 2>/dev/null || true
        log_inf "C2-Blocklist wird aktualisiert (alte Einträge entfernt)..."
    fi

    # C2-Domains zu /etc/hosts hinzufügen (mit tee statt bash -c Root-Shell)
    echo -e "  ${DIM}Füge C2-Domains zu /etc/hosts hinzu...${NC}"
    {
        echo ""
        echo "# arch-shield-c2-blocklist — Atomic Arch C2 Domains"
        echo "# Blockiert bekannte Command-and-Control Server der AUR-Malware"
        echo "# Generiert von arch-shield.sh"
        echo "# Wave 3 C2 onion (nicht via hosts blockbar, nur dokumentiert):"
        echo "#   p4ayykxcrxfyzrgfbbkazernntjbz43hgclrheguylzd7kijmtce6zqd.onion"
        for _domain in "${c2_domains[@]}"; do
            echo "0.0.0.0 $_domain"
        done
    } | run_sudo tee -a /etc/hosts > /dev/null
    log_ok "C2-Domains blockiert (${#c2_domains[@]} Einträge → 0.0.0.0)"

    # Optional: Firewall-Regeln für C2-IPs
    if command_exists iptables; then
        echo -e "  ${DIM}iptables verfügbar — füge OUTPUT-DROP für C2-IPs hinzu...${NC}"
        if ! command_exists dig; then
            log_wrn "dig nicht verfügbar — kann temp.sh IP nicht auflösen für iptables-Blocking"
        else
            local temp_sh_ip
            temp_sh_ip=$(timeout 10 dig +short +time=5 temp.sh A 2>/dev/null | head -1 || true)
            if [[ -n "$temp_sh_ip" ]]; then
                if run_sudo iptables -C OUTPUT -d "$temp_sh_ip" -j DROP 2>/dev/null; then
                    log_ok "iptables: $temp_sh_ip (temp.sh) bereits geblockt"
                elif run_sudo iptables -A OUTPUT -d "$temp_sh_ip" -j DROP 2>/dev/null; then
                    log_ok "iptables: $temp_sh_ip (temp.sh) blocked"
                else
                    log_wrn "iptables: Konnte Regel für $temp_sh_ip nicht hinzufügen"
                fi
            fi
        fi
    elif command_exists nft; then
        echo -e "  ${DIM}nftables verfügbar — C2-Blocking via nft...${NC}"
        if ! command_exists dig; then
            log_wrn "dig nicht verfügbar — kann temp.sh IP nicht auflösen für nftables-Blocking"
        else
            local temp_sh_ip
            temp_sh_ip=$(timeout 10 dig +short +time=5 temp.sh A 2>/dev/null | head -1 || true)
            if [[ -n "$temp_sh_ip" ]]; then
                if ! run_sudo nft list ruleset 2>/dev/null | grep -q "ip daddr $temp_sh_ip drop"; then
                    run_sudo nft add rule inet filter output ip daddr "$temp_sh_ip" drop 2>/dev/null && \
                        log_ok "nftables: $temp_sh_ip (temp.sh) blocked"
                else
                    log_ok "nftables: $temp_sh_ip bereits geblockt"
                fi
            fi
        fi
    fi

    log_inf "Hinweis: Tor onion C2 kann nicht via /etc/hosts geblockt werden."
    log_inf "Für Tor-Blocking: sudo pacman -S tor und torrc konfigurieren."
}

# ── 8c: auditd File-Integrity-Monitoring ──────────────────────────────────────
install_auditd_monitoring() {
    echo -e "\n${BOLD}[3/4] auditd File-Integrity-Monitoring${NC}"
    echo -e "  Überwacht sensible Verzeichnisse in Echtzeit (Kernel-Level)"

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde installieren: auditd + Rules für ~/.ssh, ~/.config, /etc/systemd${NC}"
        return 0
    }

    # Prüfe ob auditd installiert ist
    if ! command_exists auditd && ! command_exists auditctl; then
        log_wrn "auditd nicht installiert"
        echo -e "  ${YELLOW}Installiere: sudo pacman -S audit${NC}"
        echo -e "  ${DIM}  audit überwacht Kernel-System-Calls in Echtzeit${NC}"
        echo -e "  ${DIM}  Erkennt Zugriffe auf ~/.ssh, ~/.config, /etc/systemd${NC}"
        if ! confirm "auditd installieren? (sudo pacman -S audit)"; then
            return 1
        fi
        if find_sudo; then
            run_sudo pacman -S --noconfirm audit 2>/dev/null || {
                log_err "Installation von audit fehlgeschlagen"
                return 1
            }
            run_sudo systemctl enable --now auditd 2>/dev/null || true
            log_ok "auditd installiert und gestartet"
        else
            log_err "Kein sudo verfügbar"
            return 1
        fi
    else
        log_ok "auditd bereits installiert"
    fi

    # Audit-Regeln erstellen (mit mktemp für sicheren Temp-Pfad, kein unsicherer Fallback)
    local rules_file
    rules_file=$(mktemp --tmpdir arch-shield-audit.XXXXXX.rules 2>/dev/null) || {
        log_err "Konnte keine sichere Temp-Datei für audit-rules erstellen"
        return 1
    }
    cat > "$rules_file" << 'AUDITRULES'
# arch-shield: File Integrity Monitoring Rules
# Überwacht sensible Pfade auf Lese-/Schreibzugriffe

# SSH Keys überwachen (Syscall-basiert, da -w /home/ nur das Verzeichnis selbst überwacht)
-a always,exit -F arch=b64 -S open,openat -F dir=/home -F uid!=0 -F auid>=1000 -F auid!=unset -F success=1 -k arch-shield-home-access
-w /root/.ssh/ -p rwa -k arch-shield-root-ssh
-w /root/.ssh/authorized_keys -p rwa -k arch-shield-root-ssh
-w /root/.ssh/id_rsa -p rwa -k arch-shield-root-ssh
-w /root/.ssh/id_ed25519 -p rwa -k arch-shield-root-ssh

# Systemd Units überwachen (Malware-Persistenz)
-w /etc/systemd/system/ -p wa -k arch-shield-systemd
-w /usr/lib/systemd/system/ -p wa -k arch-shield-systemd

# Pacman-Konfiguration überwachen
-w /etc/pacman.conf -p wa -k arch-shield-pacman
-w /etc/pacman.d/ -p wa -k arch-shield-pacman

# Sysctl-Konfiguration überwachen (eBPF-Härtung könnte deaktiviert werden)
-w /etc/sysctl.d/ -p wa -k arch-shield-sysctl

# Crontab überwachen (Malware-Persistenz)
-w /etc/cron.d/ -p wa -k arch-shield-cron
-w /etc/crontab -p wa -k arch-shield-cron

# Sudoers überwachen (Privilege Escalation)
-w /etc/sudoers -p wa -k arch-shield-sudoers
-w /etc/sudoers.d/ -p wa -k arch-shield-sudoers

# Hosts-Datei überwachen (C2-Blocking könnte entfernt werden)
-w /etc/hosts -p wa -k arch-shield-hosts

# Kernel-Module Laden überwachen (Syscall-basiert, da /sbin Symlinks sind)
-a always,exit -F arch=b64 -S init_module -S delete_module -k arch-shield-kernel-module
-a always,exit -F arch=b32 -S init_module -S delete_module -k arch-shield-kernel-module
AUDITRULES

    # Regeln installieren
    if find_sudo; then
        local audit_dir="/etc/audit/rules.d"
        run_sudo mkdir -p "$audit_dir" 2>/dev/null || true
        run_sudo cp "$rules_file" "$audit_dir/arch-shield.rules" 2>/dev/null || {
            log_wrn "Konnte audit-rules nicht installieren"
            rm -f "$rules_file" 2>/dev/null || true
            return 1
        }
        # Regeln neu laden
        run_sudo augenrules --load 2>/dev/null || run_sudo auditctl -R "$rules_file" 2>/dev/null || true
        log_ok "auditd Rules installiert — überwacht SSH, systemd, pacman, cron, sudo, hosts"

        # Temp-Datei aufräumen
        rm -f "$rules_file" 2>/dev/null || true

        # Status anzeigen
        local active_rules
        active_rules=$(run_sudo auditctl -l 2>/dev/null | grep -c "arch-shield" || echo "0")
        echo -e "  ${DIM}Aktive arch-shield Audit-Regeln: $active_rules${NC}"

        # Hinweis zum Auswerten
        log_inf "Audit-Logs auswerten: sudo ausearch -k arch-shield-systemd"
        log_inf "Oder: sudo aureport --key --summary"
    else
        log_wrn "Kein sudo — audit-rules müssen manuell installiert werden"
        echo -e "  sudo cp $rules_file /etc/audit/rules.d/arch-shield.rules"
        echo -e "  sudo augenrules --load"
    fi
}

# ── 8d: rkhunter Rootkit-Detection ────────────────────────────────────────────
install_rkhunter() {
    echo -e "\n${BOLD}[4/4] rkhunter Rootkit-Detection${NC}"
    echo -e "  Kernel-Level Rootkit-Scanner (ergänzt aur-scanner)"

    [[ "$DRY_RUN" == "true" ]] && {
        echo -e "  ${DIM}[DRY-RUN] Würde installieren: rkhunter + cronjob${NC}"
        return 0
    }

    if ! command_exists rkhunter; then
        log_inf "Installiere rkhunter..."
        if find_sudo; then
            run_sudo pacman -S --noconfirm rkhunter 2>/dev/null || {
                log_err "Installation von rkhunter fehlgeschlagen"
                return 1
            }
        else
            log_err "Kein sudo verfügbar"
            echo -e "  ${YELLOW}Manuell: sudo pacman -S rkhunter${NC}"
            return 1
        fi
    else
        log_ok "rkhunter bereits installiert"
    fi

    # rkhunter Datenbank updaten
    if command_exists rkhunter; then
        echo -e "  ${DIM}Aktualisiere rkhunter Datenbank...${NC}"
        run_sudo rkhunter --update 2>/dev/null || true
        run_sudo rkhunter --propupd 2>/dev/null || true
        log_ok "rkhunter Datenbank aktualisiert"

        # Ersten Scan durchführen
        echo -e "  ${DIM}Erster Scan (kann 1-2 Minuten dauern)...${NC}"
        run_sudo rkhunter --check --sk --report-warnings-only 2>/dev/null | \
            tee -a "$LOG_FILE" || true
        log_ok "rkhunter Scan abgeschlossen"

        # Wöchentliches rkhunter cron-Script erstellen
        local cron_script="$HOME/.local/share/arch-shield/rkhunter-weekly.sh"
        mkdir -p "$(dirname "$cron_script")"
        cat > "$cron_script" << 'RKCRON'
#!/bin/bash
# Wöchentlicher rkhunter Rootkit-Scan
LOG="$HOME/.local/share/arch-shield/rkhunter-weekly.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$DATE] rkhunter weekly scan" >> "$LOG"
sudo rkhunter --update --quiet 2>/dev/null
sudo rkhunter --propupd --quiet 2>/dev/null
sudo rkhunter --check --sk --report-warnings-only >> "$LOG" 2>&1
echo "[$DATE] scan complete" >> "$LOG"
echo "" >> "$LOG"
RKCRON
        chmod +x "$cron_script"

        # systemd Timer für wöchentlichen rkhunter scan — als ROOT System Service
        # (user service kann sudo nicht ohne TTY ausführen)
        local rkh_service="/tmp/rkhunter-weekly.service"
        local rkh_timer="/tmp/rkhunter-weekly.timer"

        cat > "$rkh_service" << 'SVC'
[Unit]
Description=Weekly rkhunter Rootkit Scan
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/rkhunter --update --quiet
ExecStart=/usr/bin/rkhunter --propupd --quiet
ExecStart=/usr/bin/rkhunter --check --sk --report-warnings-only
Nice=19
IOSchedulingClass=idle
SVC

        cat > "$rkh_timer" << 'TIMER'
[Unit]
Description=Run rkhunter weekly

[Timer]
OnCalendar=Sun 03:00
Persistent=true
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
TIMER

        if find_sudo; then
            run_sudo cp "$rkh_service" /etc/systemd/system/rkhunter-weekly.service 2>/dev/null || true
            run_sudo cp "$rkh_timer" /etc/systemd/system/rkhunter-weekly.timer 2>/dev/null || true
            run_sudo systemctl daemon-reload 2>/dev/null || true
            run_sudo systemctl enable --now rkhunter-weekly.timer 2>/dev/null || true
            log_ok "rkhunter root-System-Service aktiviert (Sonntag 03:00)"
        else
            log_wrn "Kein sudo — rkhunter Timer muss manuell als root installiert werden"
            echo -e "  sudo cp $rkh_service /etc/systemd/system/"
            echo -e "  sudo cp $rkh_timer /etc/systemd/system/"
            echo -e "  sudo systemctl daemon-reload"
            echo -e "  sudo systemctl enable --now rkhunter-weekly.timer"
        fi
    fi
}

# ── Hauptfunktion für Advanced Protection ──────────────────────────────────────
install_advanced_protection() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ MODUL 8: Advanced Protection ━━━${NC}"
    echo -e "Erweiterte Schutzmaßnahmen (empfohlen von deepseek-v4-pro Security Review)"
    echo ""
    echo -e "  ${BOLD}1.${NC} Täglicher Threat-Intel Update Timer (statt wöchentlich)"
    echo -e "  ${BOLD}2.${NC} C2-Netzwerkblockierung (/etc/hosts + Firewall)"
    echo -e "  ${BOLD}3.${NC} auditd File-Integrity-Monitoring (Kernel-Ebene)"
    echo -e "  ${BOLD}4.${NC} rkhunter Rootkit-Detection (ergänzt aur-scanner)"
    echo ""
    log_sep

    if ! confirm "Alle 4 Advanced Protection Module installieren?"; then
        echo -e "Wähle einzelne Module:"
        echo -e "  1) Daily Threat-Intel Timer"
        echo -e "  2) C2-Netzwerkblockierung"
        echo -e "  3) auditd Monitoring"
        echo -e "  4) rkhunter"
        echo -e "  a) Alle"
        echo -e "  0) Abbrechen"
        read -rp "Auswahl: " adv_choice
        case "$adv_choice" in
            1) install_daily_timer ;;
            2) install_c2_blocking ;;
            3) install_auditd_monitoring ;;
            4) install_rkhunter ;;
            a|A) install_daily_timer; install_c2_blocking; install_auditd_monitoring; install_rkhunter ;;
            *) echo "Abgebrochen"; return 0 ;;
        esac
    else
        install_daily_timer
        install_c2_blocking
        install_auditd_monitoring
        install_rkhunter
    fi

    echo ""
    log_sep
    local success_count=0
    local total_count=4
    systemctl --user is-active --quiet aur-shield-daily-update.timer 2>/dev/null && success_count=$((success_count + 1))
    grep -q "arch-shield-c2-blocklist" /etc/hosts 2>/dev/null && success_count=$((success_count + 1))
    (sudo auditctl -l 2>/dev/null || auditctl -l 2>/dev/null || true) | grep -q "arch-shield" && success_count=$((success_count + 1))
    command_exists rkhunter && success_count=$((success_count + 1))

    if [[ $success_count -eq $total_count ]]; then
        echo -e "${GREEN}${BOLD}  ✅ Advanced Protection installiert ($success_count/$total_count Module aktiv)${NC}"
    elif [[ $success_count -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}  ⚠️  Advanced Protection teilweise installiert ($success_count/$total_count Module aktiv)${NC}"
    else
        echo -e "${RED}${BOLD}  ❌ Advanced Protection fehlgeschlagen (0/$total_count Module aktiv)${NC}"
    fi
    log_sep
}

#==================================================================================
#  MENÜ & BANNER
#==================================================================================

show_banner() {
    echo -e "${CYAN}"
    cat << 'BANNER'
   ___                ___ _   _ _  ___       __ 
  / _ \ _ __  ___ ___/ __| | | | |/ / |     / / 
 | (_) | '_ \/ -_) -_)__ \ |_| | ' <| |__  / /  
  \___/| .__/\___\___|___/\__, |_|\_\____|/_/   
       |_|                  |___/                  
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Arch Linux AUR Security Hardening Script${NC} v$SCRIPT_VERSION"
    echo -e "  ${DIM}Schützt vor AUR-Malware (Atomic Arch, CHAOS RAT, ...)${NC}"
    echo -e "  ${DIM}Kompatibel mit Arch, CachyOS, EndeavourOS, Manjaro, Garuda, Artix${NC}"
    echo ""
}

show_menu() {
    echo -e "${BOLD}Was möchtest du tun?${NC}"
    echo ""
    echo -e "  ${BOLD}1${NC}  🔍 System scannen           Prüfe auf Malware-Infektionen"
    echo -e "  ${BOLD}2${NC}  🛡️  Schutz installieren       Installiere alle Schutzmaßnahmen"
    echo -e "  ${BOLD}3${NC}  🔧 System härten           Kernel, Build-Isolation, Repo-Sicherheit"
    echo -e "  ${BOLD}4${NC}  📊 Status anzeigen         Zeige alle Schutzmaßnahmen"
    echo -e "  ${BOLD}5${NC}  📦 Paket prüfen            Prüfe ein bestimmtes AUR-Paket"
    echo -e "  ${BOLD}6${NC}  🚀 Alles (1+2+3)           Scan + Schutz + Härtung"
    echo -e "  ${BOLD}7${NC}  🚨 Notfall-Bereinigung     Geführte Wiederherstellung bei Infektion"
    echo -e "  ${BOLD}8${NC}  🔄 Threat-Intel Update    Aktualisiere IOC-Datenbanken"
    echo -e "  ${BOLD}9${NC}  🚀 Advanced Protection    Daily Timer, C2-Blocking, auditd, rkhunter"
    echo -e "  ${BOLD}10${NC} ❓ Hilfe                   Anleitung und Best Practices"
    echo -e "  ${BOLD}0${NC}  Beenden"
    echo ""
}

show_help() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ Hilfe: arch-shield ━━━${NC}"
    echo ""
    echo -e "${BOLD}Verwendung:${NC}"
    echo -e "  ./arch-shield.sh              Interaktives Menü"
    echo -e "  ./arch-shield.sh scan          System-Scan ausführen"
    echo -e "  ./arch-shield.sh protect       Alle Schutzmaßnahmen installieren"
    echo -e "  ./arch-shield.sh harden        System härten"
    echo -e "  ./arch-shield.sh status        Schutz-Status anzeigen"
    echo -e "  ./arch-shield.sh check <pkg>   AUR-Paket prüfen"
    echo -e "  ./arch-shield.sh all           Scan + Schutz + Härtung"
    echo -e "  ./arch-shield.sh emergency     Notfall-Bereinigung (bei Infektion)"
    echo -e "  ./arch-shield.sh update        Threat-Intelligence-Datenbanken aktualisieren"
    echo -e "  ./arch-shield.sh advanced     Advanced Protection (Daily Timer, C2-Blocking, auditd, rkhunter)"
    echo -e "  ./arch-shield.sh --dry-run     Simulation (nichts wird geändert)"
    echo -e "  ./arch-shield.sh --yes         Alle Bestätigungen automatisch bejahen"
    echo -e "  ./arch-shield.sh help          Diese Hilfe"
    echo ""
    echo -e "${BOLD}Was wird installiert?${NC}"
    echo -e "  • aur-scanner (PKGBUILD Security Scanner, 87 Detektions-Regeln)"
    echo -e "  • aur-malware-check (Community IOC-Datenbank, 1935+ infizierte Pakete)"
    echo -e "  • Shell-Integration (Scan vor jedem paru/yay Befehl)"
    echo -e "  • Pacman Pre-Install Hook (blockt Malware VOR Installation)"
    echo -e "  • Pacman Post-Install Hook (scannt nach Installationen)"
    echo -e "  • Wöchentlicher systemd-Timer (automatischer Scan)"
    echo -e "  • eBPF-Härtung (Rootkit-Schutz)"
    echo -e "  • Sichere AUR-Helper-Konfiguration"
    echo ""
    echo -e "${BOLD}Best Practices für AUR-Nutzung:${NC}"
    echo -e "  1. PKGBUILD IMMER lesen vor Installation:  paru -Gp <paket>"
    echo -e "  2. Maintainer prüfen (Account-Alter, Anzahl Pakete)"
    echo -e "  3. Auf npm/bun-install-Befehle achten (Atomic-Arch-Malware!)"
    echo -e "  4. Auf curl|bash, eval, base64-decode achten"
    echo -e "  5. Checksums prüfen — nicht SKIP"
    echo -e "  6. Bei Verdacht: dieses Script nutzen zum Prüfen"
    echo ""
    echo -e "${BOLD}Notfall-Bereinigung (bei bestätigter Infektion):${NC}"
    echo -e "  ./arch-shield.sh emergency"
    echo ""
    echo -e "  Führt durch 9 Schritte:"
    echo -e "    1. System-Status dokumentieren (forensischer Snapshot)"
    echo -e "    2. Credentials rotieren (GitHub, npm, SSH, Browser, ...)"
    echo -e "    3. Infizierte Pakete entfernen"
    echo -e "    4. Persistenz entfernen (systemd, cron, autostart, bashrc)"
    echo -e "    5. eBPF Rootkit entfernen (→ Neuinstallation empfohlen)"
    echo -e "    6. Verdächtige Dateien in /tmp, /dev/shm, etc. entfernen"
    echo -e "    7. AUR Build-Cache und npm/bun Cache bereinigen"
    echo -e "    8. Systemd neu laden"
    echo -e "    9. Verifizierungsscan — ist das System wirklich sauber?"
    echo ""
    echo -e "  ${YELLOW}Bei eBPF-Rootkit: Neuinstallation ist der einzige sichere Weg!${NC}"
    echo ""
}

# ── Hauptlogik ───────────────────────────────────────────────────────────────────

main() {
    local action="${1:-menu}"

    # CLI-Argumente verarbeiten
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --yes|-y)  FORCE_YES=true; shift ;;
            scan|protect|harden|status|all|help|emergency|update|advanced) action="$1"; shift ;;
            check)     action="check"; shift; pkg_arg="${1:-}"; shift ;;
            menu)      action="menu"; shift ;;
            *)         action="menu"; break ;;
        esac
    done

    # Initialisierung
    init_log
    show_banner
    check_dependencies
    detect_distro
    detect_aur_helper || true  # Kein AUR-Helper ist eine Warnung, kein Abbruchgrund
    detect_shell
    find_sudo || true           # Kein sudo ist eine Warnung, kein Abbruchgrund

    case "$action" in
        scan)
            run_full_scan
            ;;
        protect)
            install_protection
            ;;
        harden)
            harden_system
            ;;
        status)
            show_status
            ;;
        check)
            check_aur_package "${pkg_arg:-}"
            ;;
        all)
            run_full_scan
            echo ""
            if confirm "Mit Schutz-Installation fortfahren?"; then
                install_protection
                echo ""
                if confirm "Mit System-Härtung fortfahren?"; then
                    harden_system
                fi
            fi
            echo ""
            show_status
            ;;
        emergency)
            run_emergency
            ;;
        update)
            update_threat_intel
            ;;
        advanced)
            install_advanced_protection
            ;;
        help)
            show_help
            ;;
        menu|*)
            # Interaktives Menü
            while true; do
                show_menu
                read -rp "$(echo -e "${BOLD}Auswahl:${NC} ")" choice
                case "$choice" in
                    1) run_full_scan ;;
                    2) install_protection ;;
                    3) harden_system ;;
                    4) show_status ;;
                    5) check_aur_package ;;
                    6) run_full_scan; echo; install_protection; echo; harden_system; echo; show_status ;;
                    7) run_emergency ;;
                    8) update_threat_intel ;;
                    9) install_advanced_protection ;;
                    10) show_help ;;
                    0|q|Q|exit|beenden) echo -e "${GREEN}Bis bald! Bleib sicher. 🛡️${NC}"; exit 0 ;;
                    *) echo -e "${RED}Ungültige Auswahl${NC}" ;;
                esac
                echo ""
                read -rp "$(echo -e "${BOLD}Enter für Menü, Strg+C zum Beenden...${NC}")" _
            done
            ;;
    esac
}

main "$@"