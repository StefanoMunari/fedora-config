#!/usr/bin/env bash
#
# Fedora safe sequential upgrade
#
# Usage:
#   ./fedora-upgrade.sh <current_version> <release_skip>
#
# Examples:
#   ./fedora-upgrade.sh 42 1    # Fedora 42 -> 43
#   ./fedora-upgrade.sh 42 2    # Fedora 42 -> 44
#
# Maximum supported release skip: 2
set -Eeuo pipefail

MAX_SKIP=2

die() {
    echo
    echo "ERROR: $*" >&2
    echo
    exit 1
}

info() {
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
    echo
}

pause() {
    read -rp "Premi INVIO per continuare, oppure CTRL-C per fermarti..."
}

confirm() {
    local answer
    read -rp "$1 [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ----------------------------------------------------------------------
# Argomenti
# ----------------------------------------------------------------------

[[ "$#" -eq 2 ]] || die \
    "Uso: $0 <versione_attuale> <numero_skip>"

CURRENT_ARG="$1"
SKIP="$2"

[[ "$CURRENT_ARG" =~ ^[0-9]+$ ]] ||
    die "La versione attuale deve essere un numero: $CURRENT_ARG"

[[ "$SKIP" =~ ^[0-9]+$ ]] ||
    die "Il numero di skip deve essere un numero: $SKIP"

(( SKIP >= 1 )) ||
    die "Il numero di skip deve essere almeno 1."

(( SKIP <= MAX_SKIP )) ||
    die "Non è consentito saltare più di $MAX_SKIP release."

CURRENT="$(rpm -E %fedora)"
NEXT=$((CURRENT_ARG + SKIP))

# ----------------------------------------------------------------------
# Privilegi
# ----------------------------------------------------------------------

[[ "$EUID" -ne 0 ]] ||
    die "Non eseguire questo script come root."

# ----------------------------------------------------------------------
# Controllo Fedora
# ----------------------------------------------------------------------

[[ -f /etc/fedora-release ]] ||
    die "Questo non sembra Fedora."

# ----------------------------------------------------------------------
# Verifica versione corrente
# ----------------------------------------------------------------------

if [[ "$CURRENT" != "$CURRENT_ARG" ]]; then
    die "La versione specificata ($CURRENT_ARG) non corrisponde alla "
        "versione Fedora installata ($CURRENT)."
fi

echo
echo "Fedora attuale : $CURRENT"
echo "Kernel attuale : $(uname -r)"
echo "Release skip   : $SKIP"
echo "Fedora target  : $NEXT"
echo

echo "Upgrade previsto:"
echo
echo "    Fedora $CURRENT -> Fedora $NEXT"
echo

# ----------------------------------------------------------------------
# Verifica che il sistema sia realmente aggiornato
# ----------------------------------------------------------------------

info "Controllo stato DNF"

sudo dnf check

info "Controllo aggiornamenti disponibili"

sudo dnf upgrade --refresh --assumeno

# ----------------------------------------------------------------------
# Repository
# ----------------------------------------------------------------------

info "Repository abilitati"

sudo dnf repolist --enabled

echo
echo "ATTENZIONE:"
echo "Lo script NON disabilita o rimuove repository automaticamente."
echo "I repository di terze parti possono richiedere attenzione durante"
echo "l'upgrade della release."
echo

# ----------------------------------------------------------------------
# Pacchetti extras
#
# Informativo soltanto.
# NON rimuoviamo nulla.
# ----------------------------------------------------------------------

info "Pacchetti extras"

echo "Gli extras NON vengono rimossi automaticamente."
echo

dnf repoquery --extras || true

# ----------------------------------------------------------------------
# Pacchetti duplicati
# ----------------------------------------------------------------------

info "Controllo pacchetti duplicati"

DUPLICATES="$(dnf repoquery --duplicates || true)"

if [[ -n "$DUPLICATES" ]]; then
    echo "$DUPLICATES"
    echo
    die "Trovati pacchetti duplicati. Risolvi prima di continuare."
fi

echo "Nessun pacchetto duplicato."

# ----------------------------------------------------------------------
# Kernel
# ----------------------------------------------------------------------

info "Kernel"

echo "Kernel attivo:"
uname -r

echo
echo "Kernel installati:"
rpm -qa | grep '^kernel' | sort || true

echo

# ----------------------------------------------------------------------
# Spazio disco
# ----------------------------------------------------------------------

info "Spazio disco"

df -h /
echo
df -h "$HOME"

# ----------------------------------------------------------------------
# Backup
#
# SOLO configurazione e inventari.
# NON viene fatto backup della HOME.
# ----------------------------------------------------------------------

BACKUP_DIR="$HOME/fedora-upgrade-backup-${CURRENT}-to-${NEXT}-$(date +%Y%m%d-%H%M%S)"

info "Backup configurazione"

mkdir -p "$BACKUP_DIR"

echo "Backup:"
echo "  $BACKUP_DIR"
echo

cat /etc/fedora-release \
    > "$BACKUP_DIR/fedora-release.txt"

uname -a \
    > "$BACKUP_DIR/uname.txt"

rpm -E %fedora \
    > "$BACKUP_DIR/fedora-version.txt"

rpm -qa | sort \
    > "$BACKUP_DIR/packages.txt"

dnf repoquery --userinstalled 2>/dev/null |
    sort \
    > "$BACKUP_DIR/user-installed-packages.txt" || true

dnf repolist --all \
    > "$BACKUP_DIR/repositories.txt"

# Copia repository
sudo cp -a \
    /etc/yum.repos.d \
    "$BACKUP_DIR/yum.repos.d"

# Copia configurazione DNF
sudo cp -a \
    /etc/dnf \
    "$BACKUP_DIR/dnf"

# Copia configurazione RPM
sudo cp -a \
    /etc/rpm \
    "$BACKUP_DIR/rpm"

# ----------------------------------------------------------------------
# Backup /etc
# ----------------------------------------------------------------------

info "Backup /etc"

sudo tar -czf \
    "$BACKUP_DIR/etc.tar.gz" \
    /etc

sudo chown "$USER:$USER" \
    "$BACKUP_DIR/etc.tar.gz"

ls -lh "$BACKUP_DIR/etc.tar.gz"

# ----------------------------------------------------------------------
# Repository Git
#
# Solo inventario, nessuna modifica.
# ----------------------------------------------------------------------

info "Repository Git nella HOME"

find "$HOME" \
    -type d \
    -name .git \
    -prune \
    -print \
    2>/dev/null \
    > "$BACKUP_DIR/git-repositories.txt" || true

cat "$BACKUP_DIR/git-repositories.txt" || true

# ----------------------------------------------------------------------
# Pacchetti manuali
# ----------------------------------------------------------------------

info "Pacchetti installati manualmente"

dnf repoquery --userinstalled 2>/dev/null |
    sort || true

# ----------------------------------------------------------------------
# Conferma prima di aggiornare
# ----------------------------------------------------------------------

info "Pronto per Fedora $CURRENT -> Fedora $NEXT"

echo "NON verranno:"
echo
echo "  - rimossi pacchetti"
echo "  - modificati file nella HOME"
echo "  - usati --allowerasing"
echo "  - effettuati reboot automatici"
echo
echo "Verrà invece:"
echo
echo "  1. aggiornata Fedora $CURRENT"
echo "  2. installato dnf-plugin-system-upgrade"
echo "  3. scaricato l'upgrade verso Fedora $NEXT"
echo "  4. lasciato a te il reboot"
echo

pause

# ----------------------------------------------------------------------
# Aggiornamento completo release corrente
# ----------------------------------------------------------------------

info "Aggiornamento Fedora $CURRENT"

sudo dnf upgrade --refresh

# ----------------------------------------------------------------------
# Verifica dopo aggiornamento
# ----------------------------------------------------------------------

info "Verifica post-update"

sudo dnf check

# ----------------------------------------------------------------------
# Plugin system-upgrade
# ----------------------------------------------------------------------

info "Installazione dnf-plugin-system-upgrade"

sudo dnf install -y \
    dnf-plugin-system-upgrade

# ----------------------------------------------------------------------
# Download upgrade
# ----------------------------------------------------------------------

info "Download Fedora $CURRENT -> Fedora $NEXT"

echo "Download dell'upgrade."
echo
echo "NON verrà usato --allowerasing."
echo

sudo dnf system-upgrade download \
    --releasever="$NEXT" \
    --refresh

# ----------------------------------------------------------------------
# Fine download
# ----------------------------------------------------------------------

info "DOWNLOAD COMPLETATO"

echo "Fedora $CURRENT -> Fedora $NEXT è pronta."

echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo

echo "Adesso NON riavvio automaticamente."

echo
echo "Quando hai verificato che non ci siano errori sopra:"
echo
echo "    sudo dnf system-upgrade reboot"
echo

echo "Durante il reboot Fedora eseguirà l'upgrade offline."
echo

echo "Dopo il reboot aspetta che KDE sia completamente avviato,"
echo "poi esegui:"
echo
echo "    cat /etc/fedora-release"
echo "    uname -r"
echo "    sudo dnf check"
echo "    sudo dnf upgrade --refresh"
echo

echo "Se tutto è OK, per il prossimo upgrade:"
echo
echo "    $0 $NEXT 1"
echo
echo "oppure, se vuoi saltare due release:"
echo
echo "    $0 $NEXT 2"

info "Fine Fedora $CURRENT -> Fedora $NEXT"

