#!/bin/bash
# Jednoducha instalacia Domoticz 2024.4 do /home/RTTSK/smartdryfog

# Zastavime pri chybe
set -e

# Aktualizacia systemu
echo "Aktualizujem system..."
sudo apt update
sudo apt upgrade -y
echo -----------------------------------------update dokonceny-------------

# Instalacia zavislosti
echo "Instalujem zavislosti..."
sudo apt install -y libssl-dev git libcereal-dev build-essential cmake \
    libboost-dev libboost-thread-dev libboost-system-dev libsqlite3-dev \
    curl libcurl4-openssl-dev libusb-dev zlib1g-dev python3-dev \
    liblua5.3-dev pkg-config
    
echo -----------------------------instalacia zavislosti dokoncena------------

# Stiahnutie Domoticz
echo "Stiahavam Domoticz 2024.4..."
cd /tmp
wget https://github.com/domoticz/domoticz/releases/download/2024.4/domoticz_linux_armv7l.tgz

# Vytvorenie adresara a rozbalenie
echo "Vytvoram adresar a rozbalujem..."
mkdir -p /home/RTTSK/smartdryfog
tar -xzf domoticz_linux_armv7l.tgz -C /home/RTTSK/smartdryfog

# Nastavenie opravneni
echo "Nastavujem opravnenia..."
sudo chown -R RTTSK:RTTSK /home/RTTSK/smartdryfog
sudo chmod +x /home/RTTSK/smartdryfog/domoticz

# Stiahnutie a instalacia init scriptu z GitHubu
echo "Stiahavam init script z GitHubu..."
wget https://raw.githubusercontent.com/Mibeus/smartdryfog/main/domoticz.sh -O /tmp/domoticz.sh
sudo cp /tmp/domoticz.sh /etc/init.d/
sudo chmod +x /etc/init.d/domoticz.sh

# Registracia init scriptu
echo "Registrujem init script..."
sudo update-rc.d domoticz.sh defaults

# Spustenie sluzby
echo "Spustam sluzbu domoticz..."
sudo service domoticz.sh start

# Cistenie
echo "Cistenie..."
rm -f /tmp/domoticz_linux_armv7l.tgz
rm -f /tmp/domoticz.sh

echo "Instalacia dokoncena!"
echo "Domoticz je dostupny na: http://$(hostname).local:8086"
echo "Ovladanie sluzby:"
echo "  sudo service domoticz.sh start"
echo "  sudo service domoticz.sh stop"
echo "  sudo service domoticz.sh restart"
echo "  sudo service domoticz.sh status"
echo ""
echo "Stlacte lubovolne tlacidlo pre ukoncenie..."
read -n 1 -s