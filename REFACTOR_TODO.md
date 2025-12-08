# Dotfiles Refactoring TODO

## Ziel
Umbau des Dotfiles-Projekts von public zu private repo mit Multi-Machine-Support, dabei alle Rollen für alle Geräte verfügbar halten.

## Phase 1: Script Verbesserungen

### 1.1 Code-Deduplizierung
- [x] `arch_setup()` und `endeavouros_setup()` zusammenführen → `arch_based_setup()`
- [x] Gemeinsame Logik in separate Funktionen extrahieren
- [x] Veraltete/kommentierte 1Password-Code entfernen
- [x] Ungenutzte Variablen entfernen (VAULT_SECRET_FILE, OP_*, ID)
- [x] Shellcheck-Warnungen beheben

### 1.2 Git Repository Handling
- [x] SSH-basiertes Clone für private repos implementiert
- [x] Fallback auf HTTPS falls SSH fehlschlägt
- [x] Git-URL in Konfigurationsdatei auslagern
- [x] Branch-Auswahl ermöglichen
- [x] Bessere Fehlerbehandlung beim Clone/Pull

### 1.3 Fehlerbehandlung
- [ ] Bessere Fehlerbehandlung statt `set -e`
- [ ] Sinnvolle Fehlermeldungen für häufige Probleme
- [ ] Optionales Debug-Logging

### 1.4 Konfiguration
- [ ] Locale-Einstellungen konfigurierbar machen
- [ ] Dotfiles-Verzeichnis-Pfad konfigurierbar
- [ ] Branch-Auswahl ermöglichen

## Phase 2: Multi-Machine Support

### 2.1 Inventory-Struktur
- [ ] `inventory/host_vars/` Verzeichnis erstellen
- [ ] Template für Host-spezifische Variablen
- [ ] Hostname-basierte automatische Auswahl

### 2.2 Host-spezifische Konfiguration
- [ ] Beispiel-Configs für Laptop/Desktop/Server
- [ ] Dokumentation für neue Hosts
- [ ] `.gitignore` für sensible Host-Daten erweitern

### 2.3 Rollen-Konfiguration
- [ ] Per-Host Rollen-Override-Mechanismus
- [ ] Host-spezifische Variablen in Rollen (z.B. Battery-Tools nur auf Laptop)
- [ ] Conditional-Logik für Hardware-spezifische Features

## Phase 3: Ansible-Verbesserungen

### 3.1 Main Playbook
- [ ] Debug-Tasks entfernen (aus battery branch)
- [ ] Rollen-Selection-Logik vereinfachen
- [ ] Pre-tasks aufräumen

### 3.2 Rollen
- [ ] `vs-codium` zu `vs-code` umbenennen und anpassen
- [ ] Alle Rollen auf konsistente Struktur prüfen
- [ ] become/sudo Verwendung vereinheitlichen

### 3.3 LastPass Integration
- [ ] Fehlerbehandlung in git-Rolle verbessern
- [ ] Optional machen (für Geräte ohne LastPass)
- [ ] Alternative Secret-Management-Optionen dokumentieren

## Phase 4: Dokumentation

### 4.1 README
- [ ] Installation für private repos dokumentieren
- [ ] SSH-Key Setup dokumentieren
- [ ] Multi-Machine Setup dokumentieren

### 4.2 Host-Konfiguration
- [ ] Guide für neues Gerät erstellen
- [ ] Best Practices dokumentieren
- [ ] Troubleshooting-Sektion

### 4.3 Beispiele
- [ ] Beispiel-Host-Konfigurationen
- [ ] Beispiel für Custom-Rollen
- [ ] CI/CD für private repos (optional)

## Phase 5: Testing & Cleanup

### 5.1 Testing
- [ ] Script auf frischem System testen
- [ ] Multi-Host-Setup testen
- [ ] Rollback-Mechanismus testen

### 5.2 Cleanup
- [ ] `noroles_old/` Verzeichnis aufräumen oder entfernen
- [ ] Ungenutzte pre_tasks entfernen
- [ ] .gitignore vervollständigen

### 5.3 Merge
- [ ] Branch in main mergen
- [ ] Tags für Versionen erstellen
- [ ] Changelog erstellen

## Notizen

### Beibehaltene Features
- ✅ Einfacher `dotfiles` Befehl
- ✅ Automatisches Update bei jedem Run
- ✅ Alle Rollen verfügbar für alle Hosts
- ✅ OS-Detection
- ✅ LastPass-Integration

### Neue Features
- 🆕 Private Repository Support
- 🆕 Host-spezifische Konfigurationen
- 🆕 Bessere Fehlerbehandlung
- 🆕 Konfigurierbare Settings
- 🆕 Saubererer Code

### Offene Fragen
- [ ] Welche Locale soll default sein?
- [ ] Soll ansible-galaxy automatisch laufen?
- [ ] Branch-Strategie für verschiedene Hosts?
