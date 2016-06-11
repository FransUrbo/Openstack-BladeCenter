#!/bin/sh

# PXE auto installer - PART ONE

do_install() {
    apt-get -y --no-install-recommends install $*
}

set -ex

export DEBIAN_FRONTEND="noninteractive"

# Get the basic setup files (ssh/gpg keys etc)
cd /var/tmp
wget http://localserver/PXEBoot/new_blade.tgz
cd /

# Unpack the basic setup files
tar xvzf /var/tmp/new_blade.tgz

# Make sure we can login as root
sed -i "s@^PermitRootLogin@#PermitRootLogin@" /etc/ssh/sshd_config
echo 'PubkeyAcceptedKeyTypes=+ssh-dss' >> /etc/ssh/sshd_config

# Get extra repository keys
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 8E234FB17DFFA34D # Turbo Fredriksson
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys FADD8D64B1275EA3 # HPE

apt-get update

apt-get -y dist-upgrade

hostname="$(cat /etc/hostname)"
if echo "${hostname}" | grep -iq "^blade[A-Z][0-9][0-9]"; then
    # A blade!
    do_install hp-snmp-agents hponcfg debconf-utils ldap-utils open-iscsi dbconfig-mysql
    sed -i "s@'false'@'true'@" /etc/dbconfig-common/config

    # Need to do the rest of the install after a reboot, in the "real"
    # OS. This because systemd refuses to start MySQL etc in the chroot.
    sed -i "s@^\(exit.*\)\$@\
# Discover all targets on Localserver.\\
iscsiadm -m discovery -t st -p localserver:3260 > /dev/null\\
#host=\"\$(hostname | sed \"s\@\(blade.*\)[a-z]\@\\\1\@\" | tr '[:upper:]' '[:lower:]')\"\\
#iscsiadm -m node -p localserver:3260 -l \\\ \\
#    -T iqn.2012-11.tld.domain:share.virtualmachines.blade.center.1.\${host}\\
\\
# Run part two of the PXE auto installer.\\
sh /var/tmp/rc.install &\\
\\
exit 0\\
@" /etc/rc.local
fi

apt-get -y autoremove
apt-get -y clean
