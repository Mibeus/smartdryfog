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


# Instalacia monit
echo "Instalujem Monit..."
sudo apt-get install -y monit

# Uprava monitrc pre kontrolu Domoticz
echo "Upravenie monitrc..."
sudo bash -c "cat > /etc/monit/monitrc << 'EOFMONIT'
set daemon 120      #check services at 2-minute intervals
set log /var/log/monit.log
set idfile /var/lib/monit/id
set statefile /var/lib/monit/state
set eventqueue
    basedir /var/lib/monit/events
    slots 100
set httpd port 2812
use address localhost
allow localhost
allow admin:monit
check process domoticz with pidfile /var/run/domoticz.pid
  start program = \"/usr/bin/sudo /bin/systemctl start domoticz.service\"
  stop  program = \"/usr/bin/sudo /bin/systemctl stop domoticz.service\"
  if failed
     url http://127.0.0.1:8086/json.htm?type=command&param=getversion
         and content = '\"status\" : \"OK\"'
     for 2 cycles
     then restart
  if 5 restarts within 5 cycles then exec \"/sbin/reboot\"
include /etc/monit/conf.d/*
include /etc/monit/conf-enabled/*
EOFMONIT"

# Nastavenie spravnych opravneni
sudo chmod 700 /etc/monit/monitrc

# Instalacia WiringPi
echo "Instalujem WiringPi..."
cd /tmp
wget https://project-downloads.drogon.net/wiringpi-latest.deb
sudo dpkg -i wiringpi-latest.deb
gpio -v

# Instalacia Mosquitto
echo "Instalujem Mosquitto..."
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable mosquitto.service

# Vytvorenie uzivatela pre MQTT
echo "Vytvoram MQTT uzivatela..."
sudo mosquitto_passwd -c /etc/mosquitto/passfile dryfogmqtt
mosquitto -h | grep version

# Uprava konfiguracie Mosquitto
echo "Upravenie konfiguracie Mosquitto..."
sudo bash -c "cat >> /etc/mosquitto/mosquitto.conf << 'EOFMOSQUITTO'
# Zakladna konfiguracia
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto/mosquitto.log

# Nastavenie autentifikacie
listener 1883
password_file /etc/mosquitto/passfile
allow_anonymous false
EOFMOSQUITTO"

# Instalacia rpi.gpio a RTC knihovni
echo "Instalujem rpi.gpio a RTC knihovnu..."
sudo apt-get -y install python3-rpi.gpio
wget https://github.com/Mibeus/smartdryfog/raw/main/rpi.rtc-master.zip
unzip rpi.rtc-master.zip -d /home/RTTSK

# Instalacia RTC kniznice
cd /home/RTTSK/rpi.rtc-master
sudo python3 setup.py install

# Kontrola zapojenia RTC pred pouzitim
echo "Kontrolujem zapojenie RTC modulu..."
if /usr/local/bin/ds1302_get_utc 2>&1 | grep -q "error with RTC chip"; then
  echo "VAROVANIE: Problem s RTC modulom - skontrolujte zapojenie!"
  echo "Pokracujem bez nastavenia casu z RTC..."
else
  # Nastavenie systemoveho casu z RTC
  echo "Nastavujem cas z RTC..."
  sudo date -s "$(/usr/local/bin/ds1302_get_utc)"
fi

# Uprava rc.local a boot config
echo "Upravenie rc.local a boot konfiguracie..."
sudo chmod +x /etc/rc.local

# Pridanie RTC synchronizacie do rc.local s kontrolou chyb
sudo bash -c "cat >> /etc/rc.local << 'EOFRCLOCAL'
#!/bin/sh -e
# Synchronizacia casu z RTC pri starte
if /usr/local/bin/ds1302_get_utc 2>&1 | grep -q \"error with RTC chip\"; then
  echo \"VAROVANIE: Problem s RTC modulom - skontrolujte zapojenie!\"
else
  RTC_TIME=\$(/usr/local/bin/ds1302_get_utc)
  [ -n \"\$RTC_TIME\" ] && date -s \"\$RTC_TIME\"
fi
# Spustenie init skriptu pre Domoticz GPIO
/etc/init.d/domoticz.sh
exit 0
EOFRCLOCAL"

# Uprava boot konfiguracie
sudo bash -c "cat >> /boot/config.txt << EOFBOOTCONFIG
dtoverlay=gpio-shutdown
enable_uart=1
EOFBOOTCONFIG"

# Instalacia Cloudflared
echo "Instalujem Cloudflared..."
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm
sudo cp ./cloudflared-linux-arm /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
cloudflared -v

# Instalacia Samba a zdielanie priecinka
echo "Instalujem Samba a nastavujem zdielanie..."
sudo apt install -y samba samba-common-bin

# Vytvorenie priecinka pre data
mkdir -p ~/datalogs
chmod 775 ~/datalogs

# Konfiguracia Samba
sudo bash -c "cat >> /etc/samba/smb.conf << 'EOFSMB'
[datalogs]
path = /home/RTTSK/datalogs
writeable = yes
browseable = yes
public = no
create mask = 0775
directory mask = 0775
EOFSMB"

# Vytvorenie Samba uzivatela
sudo smbpasswd -a RTTSK

# Spustenie sluzieb
echo "Spustam a povolujem sluzby..."
sudo systemctl enable monit
sudo systemctl enable mosquitto
sudo systemctl enable domoticz

sudo systemctl start monit
sudo systemctl start mosquitto
sudo systemctl restart smbd

# Kontrola stavu sluzieb
echo "Kontrola stavu sluzieb:"
echo "----------------------"
echo "Monit:"
sudo systemctl status monit --no-pager
echo "----------------------"
echo "Mosquitto:"
sudo systemctl status mosquitto --no-pager
echo "----------------------"
echo "Samba:"
sudo systemctl status smbd --no-pager
echo "----------------------"

echo "Instalacia a konfiguracia je dokoncena!"
echo "Domoticz bude pristupny na: http://localhost:8086"
echo "Monit bude pristupny na: http://localhost:2812"
echo "MQTT broker je pristupny na porte 1883 (vyzaduje autentifikaciu)"
echo "Samba zdielanie je dostupne na: \\\\$(hostname)\\datalogs"