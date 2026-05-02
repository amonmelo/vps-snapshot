<p align="center"><img src="assets/logo.svg" alt="VPS Snapshot" width="480"></p>

<p align="center">
  🇧🇷 <a href="README.md">Portugues</a> · 🇺🇸 <a href="README.en.md">English</a> · 🇪🇸 <a href="README.es.md">Español</a> · 🇩🇪 <strong>Deutsch</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Lizenz-MIT-green" alt="Lizenz">
  <img src="https://img.shields.io/badge/1_Befehl-Installieren-blue" alt="1 Befehl">
  <img src="https://img.shields.io/badge/Anbieter-10%2B-orange" alt="Anbieter">
</p>

<p align="center">
  <a href="#schnellstart">Schnellstart</a> ·
  <a href="#funktionen">Funktionen</a> ·
  <a href="#anbieter">Anbieter</a> ·
  <a href="#konfiguration">Konfiguration</a> ·
  <a href="#sicherheit">Sicherheit</a>
</p>

<p align="center"><strong>Vollständige VPS-Sicherung in die Cloud. Ein Befehl zum Installieren, ein Befehl zum Ausführen.</strong></p>

---

## Warum?

Manuelle VPS-Sicherungen sind fehleranfällig und unzuverlässig. Shell-Skripte funktionieren, erfordern aber Wartung. VPS Snapshot automatisiert den gesamten Prozess:

- **Sichert den gesamten VPS** – Dateien, Datenbanken und Docker-Volumes in einem Durchgang
- **Komprimiert mit pigz** – Schnelle Parallelkomprimierung zur Reduzierung der Größe
- **Verschlüsselt mit GPG** – Ende-zu-Ende-Verschlüsselung mit Ihrem eigenen Schlüssel
- **Prüft mit SHA-256** – Garantierte Datenintegrität vor und nach dem Upload
- **Läuft über cron** – Vollständig automatisierte, geplante Sicherungen
- **Sendet aufgetretene Fehler** – Benachrichtigung bei fehlgeschlagenen Sicherungen
- **Konfiguration in einer Datei** – Alle Einstellungen in `.env`

---

## Schnellstart

```bash
curl -fsSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | bash
```

Nach der Installation:

```bash
cd ~/vps-snapshot
cp .env.example .env
# Bearbeiten Sie .env mit Ihren Einstellungen
./snapshot.sh
```

---

## Funktionen

- Vollständige VPS-Sicherung (Dateien, Datenbanken, Docker-Volumes)
- Parallelkomprimierung mit pigz
- Ende-zu-Ende-GPG-Verschlüsselung
- SHA-256-Integritätsprüfung
- Unterstützung für 10+ Cloud-Speicheranbieter über rclone
- Automatisierte Sicherungen mit cron
- Fehlerbenachrichtigung
- Einfache Konfiguration über eine einzige `.env`-Datei
- Backup-Rotation und automatische Bereinigung alter Sicherungen
- Unterstützt MySQL, PostgreSQL, MariaDB und SQLite
- Benutzerdefinierte Verzeichnisse und Dateiausschlüsse
- Unterstützung für mehrere GPG-Empfänger

---

## Anbieter

| Anbieter | Kostenloser Tarif | Einrichtung |
|---|---|---|
| Amazon S3 | 5 GB | Einfach |
| Google Drive | 15 GB | Einfach |
| Dropbox | 2 GB | Einfach |
| Backblaze B2 | 10 GB | Einfach |
| Wasabi | 30 Tage Testversion | Einfach |
| Cloudflare R2 | 10 GB/Monat | Einfach |
| Hetzner Storage Box | - | Mittel |
| MinIO | - | Mittel |
| OneDrive | 5 GB | Einfach |
| Mega | 20 GB | Mittel |
| Jottacloud | 5 GB | Einfach |
| SFTP | - | Mittel |

> Alle Anbieter werden über rclone konfiguriert. Führen Sie `rclone config` aus, um einen neuen Anbieter einzurichten.

---

## Funktionsweise

VPS Snapshot führt einen mehrstufigen Sicherungsprozess aus:

1. **Ermittlung** – Ermittelt das Betriebssystem und die verfügbaren Dienste
2. **Vorbereitung** – Erstellt einen temporären Sicherungsordner
3. **Datenbanksicherung** – Sichert alle konfigurierten Datenbanken
4. **Dateisicherung** – Sichert alle konfigurierten Verzeichnisse
5. **Docker-Sicherung** – Sichert Docker-Volumes (falls konfiguriert)
6. **Komprimierung** – Komprimiert die Sicherung mit pigz
7. **Verschlüsselung** – Verschlüsselt die Sicherung mit GPG
8. **Integritätsprüfung** – Erstellt einen SHA-256-Hash
9. **Upload** – Lädt die Sicherung in die Cloud hoch über rclone
10. **Bereinigung** – Entfernt temporäre Dateien und alte Sicherungen
11. **Benachrichtigung** – Sendet eine Benachrichtigung mit dem Ergebnis

---

## Konfiguration

Kopieren Sie die Datei `.env.example` nach `.env` und passen Sie die Werte an:

```bash
cp .env.example .env
nano .env
```

### Wichtige Einstellungen

| Einstellung | Beschreibung | Standard |
|---|---|---|
| `BACKUP_NAME` | Name des Sicherungsjobs | `vps-snapshot` |
| `BACKUP_DIRS` | Zu sichernde Verzeichnisse (Leerzeichen getrennt) | `/etc /home /var/www` |
| `ENCRYPTION_ENABLED` | GPG-Verschlüsselung aktivieren | `true` |
| `GPG_RECIPIENT` | GPG-Empfänger-E-Mail oder ID | - |
| `COMPRESSION_LEVEL` | pigz-Komprimierungsstufe (1-9) | `6` |
| `RCLONE_REMOTE` | rclone-Remotename | `backup` |
| `RCLONE_DEST` | rclone-Zielpfad | `vps-backups` |
| `RETENTION_COUNT` | Anzahl der zu behaltenden Sicherungen | `7` |
| `NOTIFICATION_ENABLED` | Fehlerbenachrichtigung aktivieren | `true` |

### Datenbankkonfiguration

| Einstellung | Beschreibung | Standard |
|---|---|---|
| `MYSQL_ENABLED` | MySQL-Sicherung aktivieren | `true` |
| `POSTGRES_ENABLED` | PostgreSQL-Sicherung aktivieren | `false` |
| `SQLITE_ENABLED` | SQLite-Sicherung aktivieren | `false` |

### Cron-Konfiguration

Für automatisierte tägliche Sicherungen:

```bash
crontab -e
```

Fügen Sie Folgendes hinzu, um jeden Tag um 2 Uhr morgens eine Sicherung auszuführen:

```
0 2 * * * /home/$USER/vps-snapshot/snapshot.sh >> /var/log/vps-snapshot.log 2>&1
```

---

## Alle Befehle

| Befehl | Beschreibung |
|---|---|
| `./snapshot.sh` | Vollständige Sicherung ausführen |
| `./snapshot.sh --files` | Nur Dateien sichern |
| `./snapshot.sh --databases` | Nur Datenbanken sichern |
| `./snapshot.sh --docker` | Nur Docker-Volumes sichern |
| `./snapshot.sh --dry-run` | Testlauf ohne Hochladen |
| `./snapshot.sh --list` | Vorhandene Sicherungen auflisten |
| `./snapshot.sh --restore <datei>` | Sicherung wiederherstellen |
| `./snapshot.sh --cleanup` | Alte Sicherungen bereinigen |
| `./snapshot.sh --status` | Systemstatus und Konfiguration prüfen |
| `./snapshot.sh --version` | Version anzeigen |

---

## Sicherheit

| Ebene | Implementierung |
|---|---|
| Verschlüsselung | GPG-Verschlüsselung mit Ihrem eigenen Schlüsselpaar |
| Integrität | SHA-256-Hash-Prüfung vor und nach dem Upload |
| Übertragung | rclone mit TLS-Verschlüsselung |
| Speicherung | Verschlüsselte Dateien auf dem Cloud-Speicher |
| Schlüsselverwaltung | Ihr privater Schlüssel verlässt nie den Server |

---

## Architektur

```
vps-snapshot/
├── snapshot.sh          # Hauptskript
├── install.sh           # Installationsskript
├── lib/
│   ├── backup.sh        # Sicherungsmodule
│   ├── compress.sh      # Komprimierung mit pigz
│   ├── encrypt.sh       # GPG-Verschlüsselung
│   ├── upload.sh        # rclone-Upload
│   ├── notify.sh        # Benachrichtigungen
│   └── utils.sh         # Hilfsfunktionen
├── .env.example         # Beispielkonfiguration
├── excludes.txt         # Ausschlussliste
└── README.md            # Dokumentation
```

---

## Anforderungen

- Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- [Bun](https://bun.sh/) (wird beim Installieren automatisch installiert)
- [rclone](https://rclone.org/) (wird beim Installieren automatisch installiert)
- GPG (wird beim Installieren automatisch installiert)
- pigz (wird beim Installieren automatisch installiert)
- Ein Cloud-Speicherkonto (konfiguriert über rclone)

---

## Deinstallation

```bash
cd ~/vps-snapshot
./uninstall.sh
```

---

## Lizenz

Dieses Projekt steht unter der MIT-Lizenz – siehe die Datei [LICENSE](LICENSE) für weitere Details.

---

<p align="center">Built with <a href="https://bun.sh/">Bun</a> · Powered by <a href="https://rclone.org/">rclone</a><br>Made by <a href="https://www.linkedin.com/in/amonmelo/">Amon Melo</a></p>
