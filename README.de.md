# 🛡️ arch-shield

**Arch Linux AUR Security Hardening Script** — Schützt jedes Arch-basierte System vor AUR-Malware.

> Reaktion auf den [Atomic-Arch Supply-Chain-Angriff vom Juni 2026](https://archlinux.org/news/active-aur-malicious-packages-incident/), bei dem 1.500+ AUR-Pakete mit Credential-Stealer und eBPF-Rootkit kompromittiert wurden.

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-supported-blue.svg)](https://archlinux.org)
[![Version](https://img.shields.io/badge/version-1.5.1-green.svg)](https://github.com/leckminartor/arch-shield/releases)

**[Deutsch](README.de.md)** | **[English](README.md)**

---

## Kompatible Distributionen

Arch Linux · CachyOS · EndeavourOS · Manjaro · Garuda Linux · Artix Linux · und alle Arch-basierten Distributionen

## Schnellstart

```bash
# Herunterladen
curl -L -o arch-shield.sh https://github.com/leckminartor/arch-shield/raw/main/arch-shield.sh

# Ausführbar machen
chmod +x arch-shield.sh

# Interaktives Menü starten
./arch-shield.sh

# Oder direkt: Alles (Scan + Schutz + Härtung)
./arch-shield.sh all

# Trockenlauf (nichts wird geändert)
./arch-shield.sh --dry-run all
```

## Funktionen

| Befehl | Beschreibung |
|--------|-------------|
| `./arch-shield.sh` | Interaktives Menü |
| `./arch-shield.sh scan` | System auf Malware scannen |
| `./arch-shield.sh protect` | Alle Schutzmaßnahmen installieren |
| `./arch-shield.sh harden` | Kernel-, Build-Isolation & Repo-Härtung |
| `./arch-shield.sh status` | Schutz-Status anzeigen |
| `./arch-shield.sh check <paket>` | Bestimmtes AUR-Paket prüfen |
| `./arch-shield.sh all` | Alles: Scan + Schutz + Härtung |
| `./arch-shield.sh emergency` | **Notfall-Bereinigung bei Infektion** |
| `./arch-shield.sh update` | **Threat-Intelligence-Datenbanken aktualisieren** |
| `./arch-shield.sh --dry-run <cmd>` | Simulation (nichts wird geändert) |
| `./arch-shield.sh help` | Hilfe anzeigen |

## Module

Das Script hat **7 Module**:

1. **🔍 System-Scan** — 6-Schicht-Scan: 1935 IOC-Pakete, statische PKGBUILD-Analyse (87 Regeln), eBPF-Rootkit, npm/bun-Cache, systemd-Persistenz, pacman-Log-Historie
2. **🛡️ Schutz installieren** — aur-scanner, aur-malware-check, Shell-Integration, Pre/Post-Install Hooks, wöchentlicher systemd-Timer
3. **🔧 System härten** — eBPF-Härtung, Build-Isolation (Chroot), Repo-SigLevel-Prüfung, AUR-Helper-Konfiguration, Firewall-Status
4. **📊 Status** — Übersicht aller installierten Schutzmaßnahmen
5. **📦 Paket prüfen** — Einzelnes AUR-Paket gegen alle Datenbanken prüfen
6. **🚨 Notfall-Bereinigung** — Geführte 9-Schritt-Wiederherstellung bei Infektion (Snapshot, Credential-Rotation, Bereinigung, Verifizierung)
7. **🔄 Threat-Intel Update** — Aktualisiert IOC-Datenbanken von Community-Feeds (git pull, HedgeDoc, Arch News)

## Was installiert wird

- **aur-scanner** — PKGBUILD Security Scanner mit 87 Detektions-Regeln
- **aur-malware-check** — Community IOC-Datenbank mit 1935+ infizierten Paketen
- **Shell-Integration** — Scannt vor jedem `paru`/`yay` Befehl (bash, zsh, fish, nu)
- **Pacman Pre-Install Hook** — Blockt Malware vor der Installation (`AbortOnFail`)
- **Pacman Post-Install Hook** — Scannt nach jeder Installation
- **Wöchentlicher systemd-Timer** — Automatischer Scan + Threat-Intel-Update jeden Montag
- **eBPF-Härtung** — Rootkit-Schutz via sysctl
- **Build-Isolation** — paru Chroot-Modus für isolierte AUR-Builds
- **Sichere AUR-Helper-Konfiguration** — NewsOnUpgrade, UpgradeMenu, SaveChanges

## Was der Scan prüft

1. **1935+ bekannte infizierte Pakete** — Abgleich mit Community IOC-Datenbank
2. **Statische PKGBUILD-Analyse** — 87 Detektions-Regeln (Reverse Shells, Credential Theft, eBPF Rootkit, Cryptominer, Obfuscation, ...)
3. **eBPF-Rootkit-Spuren** — `/sys/fs/bpf/hidden_*` Maps
4. **npm/bun Cache** — Maliziöse Pakete (atomic-lockfile, js-digest, lockfile-js)
5. **Systemd-Persistenz** — Verdächtige Services mit Restart=always
6. **Pacman-Log-Historie** — Installationen im Angriffszeitraum

## Notfall-Bereinigung

Bei bestätigter Infektion führt `./arch-shield.sh emergency` durch 9 Schritte:

1. System-Status dokumentieren (forensischer Snapshot)
2. Credentials rotieren (GitHub, npm, SSH, Browser, ...)
3. Infizierte Pakete entfernen
4. Persistenz entfernen (systemd, cron, autostart, bashrc)
5. eBPF Rootkit entfernen (→ Neuinstallation empfohlen)
6. Verdächtige Dateien in /tmp, /dev/shm entfernen
7. AUR Build-Cache und npm/bun Cache bereinigen
8. Systemd neu laden
9. Verifizierungsscan — ist das System wirklich sauber?

> ⚠️ Bei eBPF-Rootkit-Erkennung wird Neuinstallation empfohlen — der Rootkit kann Prozesse und Dateien verstecken.

## Voraussetzungen

- Arch-basiertes Linux (x86_64)
- `bash` 4+
- `python3` (für aur-malware-check, optional)
- `git` (für aur-malware-check Download, optional)
- `sudo` oder `doas` (für System-Hooks und sysctl)
- Ein AUR-Helper (`paru`, `yay`, `pikaur`, `trizen`) — empfohlen

Das Script erkennt automatisch: Distribution, AUR-Helper, Shell, sudo-Verfügbarkeit und fehlende Tools.

## Code-Review

Dieses Script wurde von zwei KI-Modellen code-reviewed:
- **qwen3-coder:480b** — Bash/Security Code Review (Syntax, Quoting, Race Conditions, Robustheit)
- **deepseek-v4-pro** — Security Architecture Review (Angriffsvektoren, Build-Isolation, Repo-Sicherheit)

Es wurde in einer Distrobox Arch-Container-Umgebung getestet (Scan, Notfall-Bereinigung mit simulierter Malware).

## Quellen

- [Arch Linux Advisory](https://archlinux.org/news/active-aur-malicious-packages-incident/)
- [aur-malware-check](https://github.com/lenucksi/aur-malware-check)
- [aur-scanner](https://github.com/KiefStudioMA/ks-aur-scanner)
- [BleepingComputer Report](https://www.bleepingcomputer.com/news/security/over-400-arch-linux-packages-compromised-to-push-rootkit-infostealer/)
- [Truesec Analysis](https://www.truesec.com/hub/blog/supply-chain-attack-compromising-arch-linux-aur-packages-infostealer-rootkit)
- [CloudSecurityAlliance eBPF Rootkit Analysis](https://labs.cloudsecurityalliance.org/research/csa-research-note-aur-supply-chain-ebpf-rootkit-20260614-csa/)

## Haftungsausschluss

Dieses Projekt wird freiwillig und ohne Gewähr bereitgestellt.

**Es wird KEINERLEI Haftung übernommen** — weder für direkte noch indirekte Schäden, Datenverlust, Systemausfälle oder Sicherheitsvorfälle, die aus der Nutzung dieses Scripts resultieren.

- ❌ **Keine Garantie** auf 100% Schutz vor allen Bedrohungen
- ❌ **Keine Garantie** auf fehlerfreie Funktion in jeder Umgebung
- ❌ **Keine Haftung** für falsche Erkennungen (False Positives) oder übersehene Bedrohungen (False Negatives)
- ❌ **Keine Haftung** für Schäden an System, Daten oder Credentials

**Die Nutzung erfolgt ausschließlich auf eigene Gefahr.**

Dieses Script ist eine Ergänzung zu — kein Ersatz für — eigene Sorgfalt, manuelle PKGBUILD-Reviews und bewährte Security-Practices. Das AUR ist ein inoffizielles, von der Community erstelltes Repository. Für jedes Paket gilt: **PKGBUILD lesen, Maintainer prüfen, verstehen was du installierst.**

## Spenden

Wenn dieses Script dir geholfen hat, freue ich mich über eine Spende:

[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://paypal.me/klausminator)

## Lizenz

GPL-3.0-or-later — siehe [LICENSE](LICENSE)
