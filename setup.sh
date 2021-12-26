#!/bin/bash -e

BOOT_CMDLINE_TXT="/boot/cmdline.txt"
BOOT_CONFIG_TXT="/boot/config.txt"

KEYBOARD="us"      # or e.g. "fi" for Finnish
TIMEZONE="Etc/UTC" # or e.g. "Europe/Helsinki"; see https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

function working {
  echo -e "\n✨  $1"
}
function question {
  echo -e "\n🛑  $1"
}

echo "User: $(whoami)"

if [ ! -f "./home/first-boot.html" ]; then
  working "Generating first-boot.html"

  if [ ! -d "node_modules" ]; then
    sudo apt update && sudo apt install -y npm
    npm install markdown-styles@3.1.10 html-inline@1.2.0
  fi

  if [ ! -d "md-input" ]; then
    mkdir md-input
    cp ./docs/first-boot.md md-input
  fi

  mkdir md-output

  cp ./docs/first-boot.md md-output

  ./node_modules/.bin/generate-md --layout github --input md-input/ --output md-output/
  ./node_modules/.bin/html-inline -i md-output/first-boot.html >./home/first-boot.html
fi

[ -d "node_modules" ] && rm -rf "node_modules"
[ -d "md-input" ] && rm -rf "md-input"

working "Backing up original boot files"
sudo cp -v "$BOOT_CMDLINE_TXT" "$BOOT_CMDLINE_TXT.backup"
sudo cp -v "$BOOT_CONFIG_TXT" "$BOOT_CONFIG_TXT.backup"

working "Disabling automatic root filesystem expansion"
echo "Updating: $BOOT_CMDLINE_TXT"
sudo sed -i "s#init=/usr/lib/raspi-config/init_resize.sh##" "$BOOT_CMDLINE_TXT"

working "Enabling SSH for first boot"
# https://www.raspberrypi.org/documentation/remote-access/ssh/
sudo touch /boot/ssh

working "Setting hostname"
# We want to do this right before reboot, so we don't get a lot of unnecessary complaints about "sudo: unable to resolve host chilipie-kiosk" (https://askubuntu.com/a/59517)
sudo hostnamectl set-hostname chilipie-kiosk
sudo sed -i 's/raspberrypi/chilipie-kiosk/g' /etc/hosts

working "Enabling auto-login to CLI"
# From: https://github.com/RPi-Distro/raspi-config/blob/985548d7ca00cab11eccbb734b63750761c1f08a/raspi-config#L955
SUDO_USER=pi
sudo systemctl set-default multi-user.target
sudo sed /etc/systemd/system/autologin@.service -i -e \"s#^ExecStart=-/sbin/agetty --autologin [^[:space:]]*#ExecStart=-/sbin/agetty --autologin $SUDO_USER #\"
# Set auto-login for TTY's 1-3
sudo ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
sudo ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty2.service
sudo ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty3.service

working "Setting timezone"
(echo '$TIMEZONE' | sudo tee /etc/timezone) && sudo dpkg-reconfigure --frontend noninteractive tzdata

working "Setting keyboard layout"
(echo -e 'XKBMODEL="pc105"\nXKBLAYOUT="$KEYBOARD"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n' | sudo tee /etc/default/keyboard) && sudo dpkg-reconfigure --frontend noninteractive keyboard-configuration

working "Shortening message-of-the-day for logins"
sudo rm /etc/profile.d/sshpwd.sh
echo | sudo tee /etc/motd

working "Installing packages"
sudo apt-get update && sudo apt-get install -y vim matchbox-window-manager unclutter mailutils nitrogen jq chromium-browser xserver-xorg xinit rpd-plym-splash xdotool
# We install mailutils just so that you can check "mail" for cronjob output

working "Setting home directory default content"
sudo rm -rfv /home/pi/*
sudo cp -r ./home/* /home/pi

working "Setting splash screen background"
sudo rm /usr/share/plymouth/themes/pix/splash.png && sudo ln -s /home/pi/background.png /usr/share/plymouth/themes/pix/splash.png

working "Installing default crontab"
crontab /home/pi/crontab.example

working "Making boot quieter (part 1)" # https://scribles.net/customizing-boot-up-screen-on-raspberry-pi/
echo "Updating: $BOOT_CONFIG_TXT"
sudo sed -i "s/#disable_overscan=1/disable_overscan=1/g" "$BOOT_CONFIG_TXT"
echo -e "\ndisable_splash=1" | sudo tee --append "$BOOT_CONFIG_TXT"

working "Making boot quieter (part 2)" # https://scribles.net/customizing-boot-up-screen-on-raspberry-pi/
echo "You may want to revert these changes if you ever need to debug the startup process"
echo "Updating: $BOOT_CMDLINE_TXT"
sudo sed -i 's/console=tty1/console=tty3/' "$BOOT_CONFIG_TXT"
sudo sed -i 's/$/ splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0/' "$BOOT_CONFIG_TXT"
