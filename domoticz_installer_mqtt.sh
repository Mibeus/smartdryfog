#!/bin/bash
# Jednoducha instalacia Domoticz 2024.4 do /home/RTTSK/smartdryfog

# Zastavime pri chybe
set -e


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