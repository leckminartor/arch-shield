# 🔒 CachyOS / Arch Linux AUR-Schutzplan
## Nach dem "Atomic Arch" Supply-Chain-Angriff vom Juni 2026

> **Stand:** 23. Juni 2026  
> **System:** CachyOS (Arch Linux), Kernel 7.0.12-1-cachyos  
> **Status:** ✅ System ist CLEAN — keine Infektion gefunden

---

## 📋 Was passiert ist — Der "Atomic Arch" Angriff

### Zusammenfassung

Am **11. Juni 2026** wurde eine massiven Supply-Chain-Attacke auf das **Arch User Repository (AUR)** entdeckt. Angreifer haben **1.500–2.000 verwaiste (orphaned) AUR-Pakete** übernommen und deren `PKGBUILD`- und `.install`-Dateien mit Malware modifiziert.

### Angriffsvektoren

#### Welle 1: `atomic-lockfile` / `lockfile-js` (npm)
1. Angreifer haben Identitäten legitimer Maintainer (z.B. `arojas`) via **Git-Commit-Fälschung** imitiert
2. Verwaiste Pakete übernommen
3. `npm install atomic-lockfile` oder `npm install lockfile-js` in `.install` und `.hook` Dateien injiziert
4. Die npm-Pakete enthielten einen `preinstall`-Hook, der `./src/hooks/deps` ausführt
5. `deps` ist ein **Rust-basierter Credential-Stealer** (ELF-Binary)

#### Welle 2: `js-digest` (bun)
1. Zusätzliche Angreifer-Accounts (`custodiatovar`, `veramagalhaes`) übernahmen verwaiste Pakete
2. `bun install js-digest` in PKGBUILD/`.install`-Dateien injiziert
3. Gleicher npm-Publisher `herbsobering`
4. Eingebetteter ELF-Payload mit gleicher Funktionalität

### Malware-Fähigkeiten

| Fähigkeit | Details |
|-----------|---------|
| **Credential Theft** | Discord-Tokens, GitHub-PATs, npm-Tokens, Slack-Sessions, Teams/M365-Sessions, SSH-Keys, Vault-Tokens, Docker/Podman-Credentials, Browser-Cookies |
| **Data Exfiltration** | Uploads zu `temp.sh`, C2 via Tor Onion Service |
| **Persistenz** | systemd-Services (root oder user mode) mit `Restart=always` |
| **eBPF Rootkit** | Wenn als root mit `CAP_BPF` ausgeführt: versteckt Prozesse, Dateien und Socket-Inodes |
| **Cryptominer** | Referenzen auf `/usr/bin/monero-wallet-gui` |

### Bekannte Angreifer-Accounts
- `krisztinavarga`, `franziskaweber`, `tobiaswesterburg`, `ellenmyklebust`
- `custodiatovar`, `veramagalhaes`
- `ivonahruskova` (Account 11. Jun erstellt, 16 Adoptionen)
- `simongeisler` (3 Tage alt, 16 Adoptionen)

### Vorherige Vorfälle
- **Juli 2018:** `xeactor` übernimmt `acroread` (PDF Viewer) mit Malware
- **Juli 2025:** Gefälschte Browser-Pakete mit Remote Access Trojan (CHAOS RAT)
- **August 2025:** Woche-langer DDoS-Angriff auf Arch Linux

---

## ✅ Sofortmaßnahmen — Bereits durchgeführt

### 1. System-Scan: CLEAN ✅
- **aur-malware-check** (Community-Tool, 1935 bekannte infizierte Pakete): CLEAN
- **aur-scan system** (118 Detektions-Regeln): Nur 1 False-Positive (google-chrome Cron-Rest mit Erklärungs-Befehl `rm -r`)
- **eBPF Rootkit-Check:** Keine versteckten Maps
- **npm/bun Cache-Check:** Keine Malware-Pakete
- **systemd-Persistenz-Check:** Keine verdächtigen Services
- **pacman.log-Historie:** Keine infizierten Installationen

### 2. Fish-Shell-Integration aktiviert ✅
- `source /usr/share/aur-scan/integration.fish` in `~/.config/fish/config.fish` eingetragen
- Scannt automatisch vor jedem `paru -S` / `paru -Syu` Befehl
- Interaktiver Modus: fragt vor Installation bei Funden

### 3. Benutzer-IOC-Datenbank erstellt ✅
- `~/.local/share/aur-scanner/ioc.toml` mit Atomic-Arch- und CHAOS-RAT-Kampagnen

### 4. Wöchentlicher systemd-Scan-Timer aktiviert ✅
- Service: `aur-scan-weekly.service` (user-level)
- Timer: `aur-scan-weekly.timer` — läuft jeden Montag
- Führt `aur-scan system`, `aur-malware-check`, eBPF-Check, npm/bun-Cache-Check aus
- Log: `~/.local/share/aur-scanner/scan-log.txt`

### 5. Sichere paru.conf erstellt ✅
- `NewsOnUpgrade`: Zeigt Arch-News vor jedem Upgrade
- `CombinedUpgrade`: Repo + AUR zusammen
- `UpgradeMenu`: Pakete können abgewählt werden
- `SaveChanges`: PKGBUILD-Änderungen werden gespeichert
- `RemoveMake` / `CleanAfter`: Build-Umgebung wird bereinigt

---

## ⚠️ Manuell durchzuführen (benötigt sudo)

### 6. Pre-Install pacman-Hook installieren
```bash
sudo cp /tmp/aur-scan-pre-install.hook /etc/pacman.d/hooks/aur-scan-pre-install.hook
```

### 7. eBPF-Härtung aktivieren (CRITICAL — Rootkit-Schutz)
```bash
sudo cp /tmp/99-arch-shield-ebpf.conf /etc/sysctl.d/99-arch-shield-ebpf.conf
sudo sysctl -p /etc/sysctl.d/99-arch-shield-ebpf.conf
```

### 8. CachyOS Repo absichern (CRITICAL — Supply-Chain-Schutz)
```bash
sudo sed -i 's/SigLevel = Optional TrustAll/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
```

### 9. Build-Isolation aktivieren (CRITICAL — verhindert Credential-Diebstahl)
```bash
sudo pacman -S devtools
echo 'Chroot' >> ~/.config/paru/paru.conf
```

### 7. (Optional) Sudo-Timeout verlängern für paru
```bash
# In /etc/sudoers.d/10-paru:
# Defaults!/usr/bin/makepkg timestamp_timeout=30
```

---

## 🛡️ Langfristige Schutzstrategie

### A. Allgemeine AUR-Regeln

1. **PKGBUILD IMMER reviewen** — Lese jeden `PKGBUILD` und jede `.install`-Datei vor der Installation
   ```bash
   paru -Si <paket>          # Info anzeigen
   paru -Gp <paket>          # PKGBUILD anzeigen
   ```

2. **Maintainer prüfen** — Klicke im AUR auf den Maintainer-Namen. 
   - Wie lange ist der Account alt?
   - Wie viele Pakete pflegt er?
   - ⚠️ Neu erstellte Accounts mit vielen Adoptionen = Red Flag

3. **Verwaiste Pakete meiden** — `Flagged out-of-date` oder `Maintainer: orphan` sind Riskant

4. **Commits prüfen** — Auf der AUR-Seite unter "View Changes" die letzten Commits ansehen

5. **Beliebtheit prüfen** — Pakete mit 0-1 Votes und kürzlich übernommen sind verdächtig

### B. NPM/Node-Spezifisch

Die Atomic-Arch-Malware wurde über npm `preinstall`-Hooks geladen:
- ⚠️ **Niemals** `npm install` oder `bun install` in einem PKGBUILD ohne genauestes Verständnis
- Auf folgende Patterns achten:
  ```
  npm install atomic-lockfile     # MALWARE
  npm install lockfile-js         # MALWARE
  bun install js-digest           # MALWARE
  npm install <unbekanntes-paket> # VERDÄCHTIG
  ```

### C. System-Härtung

1. **pacman SigLevel strikt halten:**
   ```ini
   SigLevel = Required DatabaseOptional
   ```
   Die `[cachyos]` Repo hat derzeit `SigLevel = Optional TrustAll` — das ist vom CachyOS-Team so vorgesehen, aber bei Bedarf kannst du es auf `Required` setzen.

2. **eBPF-Module einschränken (falls möglich):**
   ```bash
   # In /etc/sysctl.d/99-ebpf-hardening.conf:
   kernel.unprivileged_bpf_disabled = 1
   ```
   Das verhindert, dass nicht-root User eBPF-Programme laden (Rootkit-Schutz)

3. **Kernel lockdown (für maximale Sicherheit):**
   ```bash
   # Kernel-Parameter: lockdown=confidentiality
   ```

### D. Regelmäßige Überprüfung

1. **Wöchentlicher Scan** — Läuft automatisch via systemd timer ✅
2. **Arch-News abonnieren** — https://archlinux.org/news/ RSS feed
3. **aur-general Mailingliste beobachten** — https://lists.archlinux.org/
4. **aur-malware-check Repository** — Regelmäßig updaten:
   ```bash
   cd /tmp/aur-malware-check && git pull
   ```

### E. Notfall-Plan (falls infiziert)

1. **System NICHT ausschalten** — Erst forensische Erfassung mit vertrauenswürdigen Medien
2. **ALLE Credentials rotieren:**
   - Discord, GitHub, npm, Slack, Teams, SSH-Keys
   - Vault-Tokens, Cloud-Provider-Keys, Browser-Cookies
3. **Persistenz prüfen:**
   ```bash
   systemctl list-units --type=service --state=running
   ls -la /sys/fs/bpf/hidden_*
   ```
4. **Mit vertrauenswürdigen Medien bereinigen** — Arch ISO booten, Filesystem mounten, maliziöse systemd-Units entfernen
5. **Neuinstallation in Betracht ziehen** — eBPF-Rootkit macht System als nicht vertrauenswürdig

---

## 🔧 Installierte Schutzmaßnahmen — Übersicht

| Komponente | Status | Ort |
|------------|--------|-----|
| **aur-scanner** (v2.0.0) | ✅ Installiert | `/usr/bin/aur-scan` |
| **aur-malware-check** (v4.0) | ✅ Installiert | `/tmp/aur-malware-check/` |
| **Fish-Shell-Integration** | ✅ Aktiviert | `~/.config/fish/config.fish` |
| **Pre-Install pacman-Hook** | ⚠️ Manuell nötig | `/etc/pacman.d/hooks/aur-scan-pre-install.hook` |
| **Post-Install pacman-Hook** | ✅ Bereits aktiv | `/etc/pacman.d/hooks/aur-shield-after-install.hook` |
| **Wöchentlicher systemd Timer** | ✅ Aktiviert | `~/.config/systemd/user/aur-scan-weekly.timer` |
| **IOC-Datenbank** | ✅ Erstellt | `~/.local/share/aur-scanner/ioc.toml` |
| **Sichere paru.conf** | ✅ Aktiviert | `~/.config/paru/paru.conf` |
| **Scan-Log** | ✅ Wird geführt | `~/.local/share/aur-scanner/scan-log.txt` |

---

## 📚 Quellen

- [Arch Linux Official Advisory](https://archlinux.org/news/active-aur-malicious-packages-incident/)
- [BleepingComputer Report](https://www.bleepingcomputer.com/news/security/over-400-arch-linux-packages-compromised-to-push-rootkit-infostealer/)
- [Truesec Analysis](https://www.truesec.com/hub/blog/supply-chain-attack-compromising-arch-linux-aur-packages-infostealer-rootkit)
- [CloudSecurityAlliance eBPF Rootkit Analysis](https://labs.cloudsecurityalliance.org/research/csa-research-note-aur-supply-chain-ebpf-rootkit-20260614-csa/)
- [aur-malware-check Detection Tool](https://github.com/lenucksi/aur-malware-check)
- [Sonatype Atomic Arch Analysis](https://www.sonatype.com/blog/atomic-arch-npm-campaign-adds-malicious-dependency)
- [The Hacker News](https://thehackernews.com/2026/06/over-400-arch-linux-aur-packages.html)
- [StepSecurity Analysis](https://www.stepsecurity.io/blog/400-aur-packages-hijacked-atomic-arch-campaign)
- [FOSSForce: Arch Says All's Clear](https://fossforce.com/2026/06/arch-says-alls-clear-after-aur-malware-incident-affects-1500-packages/)
- [CachyOS Forum Thread](https://discuss.cachyos.org/t/aur-compromised-almost-2000-packages-affected-20260611/31040)
- [CachyOS Forum: How to Check](https://discuss.cachyos.org/t/how-to-check-for-compromised-packages-from-the-current-aur-malware-attack/31077)

---

## 📝 Sicherheitshinweis

> ⚠️ **Das AUR ist ein unofficial, user-produced, unvetted Repository.**  
> Die einzige sichere Nutzung des AUR ist die **Überprüfung jeder einzelnen Zeile** in `PKGBUILD` und `.install`-Dateien vor der Installation.  
> — Arch Linux Team, Juni 2026