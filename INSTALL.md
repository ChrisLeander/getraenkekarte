# Digitale Getränkekarte – Installation auf Ubuntu

## Automatische Installation (empfohlen)

Auf einem frischen Ubuntu-Server (22.04 oder 24.04) mit Internetzugang:

    sudo apt update && sudo apt install -y unzip
    unzip getraenkekarte-server.zip -d getraenkekarte
    cd getraenkekarte
    sudo bash install.sh

Das Skript fragt nach deiner Domain (optional), einem Passwort (optional, sonst wird eines erzeugt) und erledigt den Rest:
Node.js, Webserver (nginx), Dienst mit Autostart, Firewall-Freigabe und auf Wunsch das HTTPS-Zertifikat.
Am Ende zeigt es dir die Adressen an.

- **Update:** Neue Dateien entpacken und `sudo bash install.sh` noch einmal starten. Passwort und Karte bleiben erhalten.
- **Ohne Rückfragen:** `DOMAIN=karte.meinclub.de ADMIN_PASSWORD=meinpasswort EMAIL=ich@meinclub.de sudo -E bash install.sh`

## Manuelle Installation (Alternative)

Der Server braucht Node.js 18 oder neuer und keine weiteren Pakete.
Ubuntu 24.04 bringt Node 18 mit. Auf Ubuntu 22.04 installierst du zuerst Node 20:

    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

## 1. Pakete installieren

    sudo apt update
    sudo apt install -y nodejs nginx unzip

## 2. Dateien einspielen

    sudo mkdir -p /opt/getraenkekarte
    sudo unzip getraenkekarte-server.zip -d /opt/getraenkekarte
    sudo useradd --system --home /opt/getraenkekarte --shell /usr/sbin/nologin getraenkekarte
    sudo chown -R getraenkekarte:getraenkekarte /opt/getraenkekarte/data

## 3. Passwort festlegen

    sudo cp /opt/getraenkekarte/deploy/getraenkekarte.env /etc/getraenkekarte.env
    sudo nano /etc/getraenkekarte.env        # ADMIN_PASSWORD ändern
    sudo chmod 600 /etc/getraenkekarte.env

## 4. Dienst starten

    sudo cp /opt/getraenkekarte/deploy/getraenkekarte.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now getraenkekarte
    sudo systemctl status getraenkekarte     # sollte "active (running)" zeigen

## 5. Webserver (nginx) einrichten

    sudo cp /opt/getraenkekarte/deploy/nginx.conf /etc/nginx/sites-available/getraenkekarte
    sudo nano /etc/nginx/sites-available/getraenkekarte   # server_name anpassen
    sudo ln -s /etc/nginx/sites-available/getraenkekarte /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx

## 6. HTTPS einschalten (wichtig wegen des Passworts)

Die Domain muss auf den Server zeigen. Dann:

    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d karte.example.de

## Benutzung

- **Bildschirm an der Bar:** Öffne `https://karte.example.de/` im Vollbild. Die Karte erscheint dunkel und im Hochformat, ohne Bedienelemente. Sie passt ihre Größe automatisch an. Sind es sehr viele Getränke, scrollt sie langsam von selbst. Sie holt sich alle 30 Sekunden die neuesten Daten und lädt sich alle 6 Stunden komplett neu.
- **Du:** Öffne `https://karte.example.de/#admin` am Handy oder Laptop (nicht am Bar-Bildschirm). Unten erscheinen die Knöpfe. „Bearbeiten“ fragt nach dem Passwort. Änderungen sind sofort gespeichert und erscheinen nach spätestens 30 Sekunden am Bildschirm.

## Bildschirm einrichten

- **Hochformat:** Stelle die Drehung im Betriebssystem des Abspielgeräts ein (bei Windows unter „Anzeige“ die Ausrichtung „Hochformat“, bei Ubuntu unter „Anzeigen“ die Drehung um 90 Grad). Die Karte füllt dann den Bildschirm.
- **Vollbild ohne Rand (Kiosk):** Mit Chrome oder Chromium: `chromium --kiosk https://karte.example.de/`
- **Bildschirm nicht abschalten:** Deaktiviere im Betriebssystem den Ruhezustand und den Bildschirmschoner.

## Sicherung und Updates

- Alle Daten liegen in `/opt/getraenkekarte/data/menu.json` (die vorherige Version in `menu.json.bak`). Zum Sichern diese Datei kopieren.
- Neue Version einspielen: Dateien ersetzen (den Ordner `data` nicht anfassen), dann `sudo systemctl restart getraenkekarte`.
- Passwort ändern: `/etc/getraenkekarte.env` bearbeiten, dann `sudo systemctl restart getraenkekarte`.
- Logs ansehen: `sudo journalctl -u getraenkekarte -f`
