#!/usr/bin/env bash
# Automatischer Installer für die digitale Getränkekarte (Ubuntu / Debian)
#
# Aufruf im entpackten Ordner:   sudo bash install.sh
# Läuft die Karte schon, aktualisiert das Skript nur die Programmdateien.
# Passwort und Karte (data/menu.json) bleiben dabei unverändert.
#
# Ohne Rückfragen (optional): DOMAIN=karte.meinclub.de ADMIN_PASSWORD=... EMAIL=... sudo -E bash install.sh

set -euo pipefail

APP_DIR=/opt/getraenkekarte
APP_USER=getraenkekarte
ENV_FILE=/etc/getraenkekarte.env
SERVICE_FILE=/etc/systemd/system/getraenkekarte.service
NGINX_SITE=/etc/nginx/sites-available/getraenkekarte
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-3000}"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mHinweis: %s\033[0m\n' "$*"; }
die()  { printf '\033[31mFehler: %s\033[0m\n' "$*" >&2; exit 1; }
ask()  { local a=""; read -r -p "$1" a || true; printf '%s' "$a"; }

[ "$(id -u)" -eq 0 ] || die "Bitte mit Administratorrechten starten:  sudo bash install.sh"
command -v apt-get >/dev/null 2>&1 || die "Dieses Skript ist für Ubuntu oder Debian gedacht (apt-get fehlt)."
[ -f "$SRC_DIR/server.js" ] && [ -f "$SRC_DIR/public/index.html" ] \
  || die "server.js oder public/index.html fehlt. Starte das Skript im entpackten Ordner."

UPDATE=0
if [ -f "$APP_DIR/server.js" ] && [ -f "$ENV_FILE" ]; then UPDATE=1; fi

DOMAIN="${DOMAIN:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
EMAIL="${EMAIL:-}"
GENERATED=0
HTTPS=0

# ---------------------------------------------------------------- Fragen
if [ "$UPDATE" -eq 0 ]; then
  if [ -t 0 ]; then
    echo "Digitale Getränkekarte – Installation"
    echo
    [ -n "$DOMAIN" ] || DOMAIN="$(ask 'Domain, z. B. karte.meinclub.de (leer lassen = nur über die IP-Adresse): ')"
    if [ -z "$ADMIN_PASSWORD" ]; then
      read -r -s -p 'Passwort zum Bearbeiten, mind. 8 Zeichen (leer lassen = automatisch erzeugen): ' ADMIN_PASSWORD || true
      echo
    fi
    if [ -n "$DOMAIN" ] && [ -z "$EMAIL" ]; then
      EMAIL="$(ask 'E-Mail für das HTTPS-Zertifikat (leer lassen = ohne E-Mail): ')"
    fi
  fi

  DOMAIN="${DOMAIN//[[:space:]]/}"
  if [ -n "$DOMAIN" ] && ! [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    die "Die Domain \"$DOMAIN\" sieht ungültig aus."
  fi
  if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
    GENERATED=1
  fi
  [ "${#ADMIN_PASSWORD}" -ge 8 ] || die "Das Passwort muss mindestens 8 Zeichen lang sein."
  case "$ADMIN_PASSWORD" in
    *\"*|*\\*|*$'\n'*) die 'Im Passwort sind die Zeichen " und \ nicht erlaubt.' ;;
  esac
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${PORT}\$"; then
    die "Port $PORT ist schon belegt. Starte mit einem anderen Port:  sudo PORT=3001 bash install.sh"
  fi
else
  PORT="$(grep -E '^PORT=' "$ENV_FILE" | head -n1 | cut -d= -f2 || true)"
  PORT="${PORT:-3000}"
  say "Vorhandene Installation gefunden – es wird nur aktualisiert"
fi

# ---------------------------------------------------------------- Pakete
if [ "$UPDATE" -eq 0 ]; then
  export DEBIAN_FRONTEND=noninteractive
  NGINX_PRE=0
  if command -v nginx >/dev/null 2>&1; then NGINX_PRE=1; fi

  say "Pakete werden installiert"
  apt-get update -y
  apt-get install -y curl ca-certificates nginx

  node_ok() {
    command -v node >/dev/null 2>&1 && [ "$(node -p 'process.versions.node.split(".")[0]')" -ge 18 ]
  }
  if ! node_ok; then
    apt-get install -y nodejs || true
  fi
  if ! node_ok; then
    say "Die Node.js-Version von Ubuntu ist zu alt – installiere Node.js 20"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi
  node_ok || die "Node.js 18 oder neuer konnte nicht installiert werden."
fi

NODE_BIN="$(command -v node)"

# ---------------------------------------------------------------- Dateien
say "Programmdateien werden eingespielt"
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi
mkdir -p "$APP_DIR/public" "$APP_DIR/data"
install -m 644 "$SRC_DIR/server.js" "$APP_DIR/server.js"
install -m 644 "$SRC_DIR/public/index.html" "$APP_DIR/public/index.html"
chown -R "$APP_USER:$APP_USER" "$APP_DIR/data"

if [ "$UPDATE" -eq 0 ]; then
  umask 077
  cat > "$ENV_FILE" <<ENVEOF
ADMIN_PASSWORD="$ADMIN_PASSWORD"
PORT=$PORT
HOST=127.0.0.1
ENVEOF
  umask 022
  chmod 600 "$ENV_FILE"
fi

# ---------------------------------------------------------------- Dienst
say "Dienst wird eingerichtet und gestartet"
cat > "$SERVICE_FILE" <<UNITEOF
[Unit]
Description=Digitale Getraenkekarte
After=network.target

[Service]
User=$APP_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$NODE_BIN server.js
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_DIR/data

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable getraenkekarte >/dev/null 2>&1
systemctl restart getraenkekarte

for _ in $(seq 1 15); do
  if curl -fsS "http://127.0.0.1:$PORT/api/me" >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -fsS "http://127.0.0.1:$PORT/api/me" >/dev/null 2>&1 \
  || die "Der Dienst startet nicht. Details:  journalctl -u getraenkekarte -n 30"

# ---------------------------------------------------------------- nginx + HTTPS
if [ "$UPDATE" -eq 0 ]; then
  say "Webserver (nginx) wird eingerichtet"
  if [ -n "$DOMAIN" ]; then LISTEN=""; SERVER_NAME="$DOMAIN"; else LISTEN=" default_server"; SERVER_NAME="_"; fi
  cat > "$NGINX_SITE" <<NGXEOF
server {
    listen 80${LISTEN};
    listen [::]:80${LISTEN};
    server_name ${SERVER_NAME};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 2m;
    }
}
NGXEOF
  ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/getraenkekarte
  if [ -z "$DOMAIN" ] && [ "$NGINX_PRE" -eq 0 ]; then rm -f /etc/nginx/sites-enabled/default; fi
  if ! nginx -t >/dev/null 2>&1; then
    rm -f /etc/nginx/sites-enabled/getraenkekarte
    die "Die nginx-Einstellungen sind ungültig (läuft auf dem Server schon eine andere Seite?). Details:  nginx -t"
  fi
  systemctl enable nginx >/dev/null 2>&1
  systemctl reload nginx 2>/dev/null || systemctl restart nginx

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 'Nginx Full' >/dev/null
  fi

  if [ -n "$DOMAIN" ]; then
    say "HTTPS-Zertifikat wird angefordert"
    apt-get install -y certbot python3-certbot-nginx
    if [ -n "$EMAIL" ]; then CB_MAIL=(-m "$EMAIL"); else CB_MAIL=(--register-unsafely-without-email); fi
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect "${CB_MAIL[@]}"; then
      HTTPS=1
    else
      warn "Das HTTPS-Zertifikat konnte nicht angefordert werden. Zeigt die Domain schon auf diesen Server?"
      warn "Wiederhole es später mit:  sudo certbot --nginx -d $DOMAIN"
    fi
  fi
fi

# ---------------------------------------------------------------- Fertig
if [ "$UPDATE" -eq 1 ]; then
  say "Fertig – die Karte wurde aktualisiert."
  exit 0
fi

if [ -n "$DOMAIN" ]; then
  if [ "$HTTPS" -eq 1 ]; then BASE="https://$DOMAIN"; else BASE="http://$DOMAIN"; fi
else
  BASE="http://$(hostname -I | awk '{print $1}')"
fi

say "Fertig – die Karte läuft."
echo
echo "  Bar-Bildschirm öffnen:   $BASE/"
echo "  Karte bearbeiten:        $BASE/#admin   (am Handy oder Laptop)"
if [ "$GENERATED" -eq 1 ]; then
  echo "  Dein Passwort:           $ADMIN_PASSWORD   (bitte jetzt notieren)"
fi
echo
if [ "$HTTPS" -eq 0 ]; then
  warn "Ohne HTTPS wird das Passwort unverschlüsselt übertragen. Richte HTTPS ein, sobald eine Domain auf den Server zeigt:"
  warn "sudo certbot --nginx -d deine-domain.de"
fi
echo "  Daten der Karte:         $APP_DIR/data/menu.json"
echo "  Passwort ändern:         sudo nano $ENV_FILE && sudo systemctl restart getraenkekarte"
echo "  Update:                  neue Dateien entpacken und erneut  sudo bash install.sh"
