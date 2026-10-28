# Digitale Getränkekarte für die Bar

Eine digitale Getränkekarte für einen Bildschirm im Hochformat an der Bar.

- **Bar-Bildschirm:** Die normale Adresse zeigt die Karte dunkel, im Hochformat und ohne Bedienelemente. Die Größe passt sich automatisch an, bei sehr vielen Getränken scrollt sie langsam von selbst.
- **Pflege:** Mit `/#admin` am Ende der Adresse meldest du dich mit Passwort an und änderst Getränke, Preise und Kategorien. Der Bildschirm aktualisiert sich nach spätestens 30 Sekunden.
- **Technik:** Node.js ohne weitere Pakete, die Daten liegen in einer einzigen Datei (`data/menu.json`).

## Installation auf einem Ubuntu-Server

```
sudo apt update && sudo apt install -y git
git clone https://github.com/DEIN-NAME/getraenkekarte.git
cd getraenkekarte
sudo bash install.sh
```

Das Skript fragt nach Domain und Passwort (beides optional) und richtet Node.js, nginx, den Dienst mit Autostart und auf Wunsch HTTPS automatisch ein.

## Update

```
cd getraenkekarte
git pull
sudo bash install.sh
```

Passwort und Karte bleiben erhalten, denn sie liegen nicht in diesem Ordner, sondern in `/opt/getraenkekarte/data` und `/etc/getraenkekarte.env`.

## Wichtig

- Nutze HTTPS (eine Domain, die auf den Server zeigt), sonst wird das Passwort unverschlüsselt übertragen.
- Sicherung: die Datei `/opt/getraenkekarte/data/menu.json` kopieren.
- Passwörter und Kartendaten gehören **nicht** ins Repository. Die `.gitignore` schließt den Datenordner aus.

Eine manuelle Installation ohne das Skript steht in `INSTALL.md`.
