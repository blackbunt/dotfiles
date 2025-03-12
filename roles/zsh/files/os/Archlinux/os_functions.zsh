#!/usr/bin/env zsh

# Funktion für das System-Update
update_system() {
  echo "🔄 Starte Systemupdate..."
  sudo pacman -Syu --noconfirm
  
  # Prüfen, ob yay oder paru vorhanden ist und AUR-Updates durchführen
  if command -v yay &> /dev/null; then
    echo "🛠 Aktualisiere AUR-Pakete mit yay..."
    yay -Syu --noconfirm
  elif command -v paru &> /dev/null; then
    echo "🛠 Aktualisiere AUR-Pakete mit paru..."
    paru -Syu --noconfirm
  else
    echo "⚠ Kein AUR-Helper (yay/paru) gefunden, AUR-Updates werden übersprungen."
  fi

  # System bereinigen
  echo "🧹 Bereinige nicht mehr benötigte Pakete..."
  sudo pacman -Sc --noconfirm
  echo "✅ Update abgeschlossen!"
}

# Standard-Alias für System-Update
alias update='update_system'

# Falls 'task' verfügbar ist, wird 'update' durch 'task -g upgrade' ersetzt
if command -v task &> /dev/null; then
  alias update='task -g upgrade'
  echo "ℹ️ 'task' gefunden – 'update' ruft jetzt 'task -g upgrade' auf."
fi
