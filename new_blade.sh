#!/bin/sh

# PXE auto installer - PART ONE.
# NOTE: This runs inside the chroot by Debian Installer.
#       Meaning, there are quite a number of things it
#       can't do, hence "Part 1".

do_install() {
    apt-get -y --no-install-recommends install $*
}

LOCALSERVER="server.domain.tld"
DEBIAN_FRONTEND="noninteractive"
export LOCALSERVER DEBIAN_FRONTEND

set -ex

# Get the basic setup files (ssh/gpg keys etc)
cd /var/tmp
wget http://${LOCALSERVER}/PXEBoot/new_blade.tgz
wget http://${LOCALSERVER}/PXEBoot/rc.install
cd /

# Unpack the basic setup files
tar xvzf /var/tmp/new_blade.tgz

# Make sure we can login as root
sed -i "s@^PermitRootLogin@#PermitRootLogin@" /etc/ssh/sshd_config

# Get extra repository keys
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8E234FB17DFFA34D # Turbo Fredriksson
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FADD8D64B1275EA3 # HPE

hostname="$(cat /etc/hostname)"
if echo "${hostname}" | grep -iq "^blade[A-Z][0-9][0-9]"; then
    # A blade!

    # Need to do the rest of the install after a reboot, in the "real"
    # OS. This because systemd refuses to start MySQL etc in the chroot.
    sed -i "s@^exit.*@\
# Discover all targets on Celia.\\
#iscsiadm -m discovery -t st -p 192.168.69.8:3260 > /dev/null\\
#host=\"\$(hostname | sed \"s\@\(blade.*\)[a-z]\@\\\1\@\" | tr '[:upper:]' '[:lower:]')\"\\
#iscsiadm -m node -p 192.168.69.8:3260 -l \\\ \\
#    -T iqn.2012-11.com.bayour:share.virtualmachines.blade.center.\${host}\\
\\
# Run part two of the PXE auto installer.\\
sh /var/tmp/rc.install \&\\
\\
exit 0\\
@" /etc/rc.local
fi

apt-get -y autoremove
apt-get -y clean
