Miscellaneous files to get my Blade Center and
PXE booting and installing without intervention.

In order of appearance:
=======================
* debian-installer_amd64_boot-screens_adtxt.cfg
* debian-installer_amd64_boot-screens_menu.cfg
  My modified version of the 
    debian-installer/amd64/boot-screens/{adtxt,menu}.cfg
  from the http://ftp.nl.debian.org/debian/dists/jessie/main/installer-amd64/current/images/netboot/netboot.tar.gz
  tarball.

* preseed_compute.cfg
  My preseed config file. Well, pretty much any
  way. It's been "cleaned" somewhat.

* new_blade.sh
  Script to unpack and do local modifications
  to the installed system.

* bladefs
  This directory is misc local stuff that's is
  in a tarball and extracted in the installed
  system root at the very latest in the install
  procedure.

  + bladefs/var/tmp/rc.install
    This is the primary installer script. That's
    where all the "magic" happens.

  This filesystem is tar'ed down into the file
  called "new_blade.tgz" in the scripts.

* blade-users.sql
  Script to setup remote access to the MySQL server
  running on the control node(s).

* debconf_openstack-control.txt
* debconf_openstack-compute.txt
  The debconf seed files.

* dbconfig-common-template.conf
  Template for the /etc/dbconfig-common/*.conf files.
  It's not enough to just seed debconf, dbconfig-common
  need these files to be able to connect to the database
  as administrator and create the databases and users.

* admin-openrc
  The file I source both in the rc.install script as well
  as when I do local modifications etc.

* install_cinder_zfs.sh
* install_nova_docker.sh
  Extra scripts to do additional installations and setup
  of locally needed stuff.

* dashboard.conf
  Simplest was just to include the whole configuration file
  for the dashboard, than to modify it with sed.
