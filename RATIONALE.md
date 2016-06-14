The ultimate point of this exercise for me is to have a simpler way to
create virtual machines and containers than my current setup - doing
it manually with the point-and-click interface in VirtualBox. Then
booting it from a CD/DVD ISO and answer each question manually. Etc.

It takes almost a day to setup a new machine for a test that might
only run for half an hour. Then the machine is not needed any more..

Yes, I end up with a lot of machines that can be reused for other things,
but different distributions, different architectures etc makes things
difficult to maintain. And because I don't have nearly enough memory
to run all of them at the same time, I have to shut them down and
start them up when needed. Time isn't free!


My current, primary, server does EVERYTHING. Everything from
LDAP/Kerberos V authentication, to serving files via SMB, NFS, AFS,
iSCSI etc, web services, much of the development and so much more.

I've always wanted/needed to move the majority of the services from
that machine to "something else". And why not use containers or VMs
for that "something else"? That will give me the opportunity to have
failovers and redundancy in those extremly important parts, and the
current server can go back to be just the file server.

Eventually, I'll even put a few hosts in "The Cloud" (other than my
own that is) so I can have off-site redundancy as well.


Enter Openstack. It's point-and-click from cold boot to finished system,
and with the upcoming "puppeting" of "things", I can ("should be able to")
simply start up a new machine in minutes, instead of hours of manual
labor.

This is why I bought a secondhand HP Blade Center c7000 with sixteen
dual processor, quad core, 16GB G6 blades. That should give me enough
processing power for the next few years :).

It was incredibly important for me that once everything is functional,
I don't need to do any manual labor! Yes, that unfortunately, as always,
means that I have to do _a lot_ of manual labor NOW. But on the other
hand, I'll be needing Openstack knowledge professionally sooner rather
than later anyway so "Two Birds With One Stone" :).


First step was to have my physical blades boot and install Openstack
without any intervention. And this is currently where I am today.

So PXE was setup, because these machines have support for that. That
was the easy part. Tweaking the install procedure to install all the
packages I needed on the different parts of the machines - two Control
nodes (because I have no real need for redundancy, I'm just doing two
because I can :) and then the other fourteen blades will become
Compute nodes.


What I learned was that I need to take this in steps. First getting the
MySQL, RabbitMQ etc up and running functionally. THEN I could deal with
Keystone. And once that works, I can do all the other.

This is where the primary script "rc.install" comes in. With this, if I
do a mistake somewhere, I can just reboot the machine with PXE boot enabled
and it will start over, leaving me with a "resonably working" setup.

Then I do local modifications to get more stuff working and if they do,
I add that to the install script and start over to make sure it's correct.

Then additional local modication etc, etc, over and over again. Eventually,
I'm going to end up with a completely working Openstack setup, which can
be blown away and reinstalled instead of "fixed" if and/or when that happens.
