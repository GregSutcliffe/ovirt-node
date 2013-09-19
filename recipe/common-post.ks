# -*-Shell-script-*-
echo "Starting Kickstart Post"
PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH

# cleanup rpmdb to allow non-matching host and chroot RPM versions
rm -f /var/lib/rpm/__db*

echo "Creating shadow files"
# because we aren't installing authconfig, we aren't setting up shadow
# and gshadow properly.  Do it by hand here
pwconv
grpconv

echo "Set root account"
echo "root:test123" | chpasswd

# Configure Foreman-proxy
sed -i 's/.*:bmc:.*/:bmc: true/' /usr/share/foreman-proxy/config/settings.yml
sed -i 's/.*:bmc_default_provider:.*/:bmc_default_provider: shell/' /usr/share/foreman-proxy/config/settings.yml

ln -s '/usr/lib/systemd/system/foreman-proxy.service' '/etc/systemd/system/multi-user.target.wants/foreman-proxy.service'

# Figure out a better way to package/download this script from the discvoery git repo...
cat >>/usr/share/foreman-proxy/bin/discover_host << \EOF_discover
#!/usr/bin/env ruby

require 'fileutils'
require 'net/http'
require 'net/https'
require 'uri'

# For comparison
require 'rubygems'
require 'facter'
require 'yaml'

def discover_server
  server = (discover_by_pxe or discover_by_dns)
  unless server =~ /^http/
    server = "http://#{server}"
  end
  server
end

def discover_by_pxe
  begin
    contents = File.open("/proc/cmdline", 'r') { |f| f.read }
    server_ip = contents.split.map { |x| $1 if x.match(/foreman.ip=(.*)/)}.compact
    if server_ip.size == 1
      return server_ip.join
    else
      return false
    end
  rescue
    return false
  end
end

def discover_by_dns
  begin
    contents = File.open("/proc/cmdline", 'r') { |f| f.read }
    server_name = contents.split.map { |x| $1 if x.match(/foreman.server=(.*)/)}.compact
    server_name = server_name.size == 1 ? server_name.join : 'foreman'

    require 'socket'
    return TCPSocket.gethostbyname(server_name)[3..-1].first || false
  rescue
    return false
  end
end

def upload
  puts "#{Time.now}: Triggering import of facts from Foreman"
  ip = Facter.value('ipaddress') 
  data = ip.nil? ? {} : {'ip' => ip}
  begin
    uri = URI.parse(discover_server)
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https' then
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    req = Net::HTTP::Post.new("/discovers")
    req.set_form_data(data)
    response = http.request(req)
    puts response.body
  rescue Exception => e
    raise "#{Time.now}: Could not send facts to Foreman: #{e}"
  end
end

def write_cache(data)
  File.open('/tmp/proxy_cache', 'w') {|f| f.write(data) }
end

def read_cache
  File.read('/tmp/proxy_cache')
rescue => e
  "empty cache"
end

# Main

$stdout.reopen("/tmp/proxy-discovery.log", "w")
$stderr.reopen("/tmp/proxy-discovery.err", "w")

# loop, but only upload on changes
while true do
  uninteresting_facts=/kernel|operatingsystem|osfamily|ruby|path|time|swap|free|filesystem|version|selinux/i
  facts = Facter.to_hash.reject! {|k,v| k =~ uninteresting_facts }
  unless YAML.load(read_cache) == facts
    puts "Fact cache invalid, reloading to foreman"
    upload
    write_cache(YAML.dump(facts))
  end
  sleep 60
end
EOF_discover
chmod 755 /usr/share/foreman-proxy/bin/discover_host

# Write a systemd file to start the discovery script on boot
cat >>/lib/systemd/system/discover-host.service << \EOF_systemd

[Unit]
Description=Discover this host to Foreman

[Service]
WorkingDirectory=/usr/share/foreman-proxy/bin
Type=forking
ExecStart=/usr/share/foreman-proxy/bin/discover_host &
KillMode=process

[Install]
WantedBy=multi-user.target
EOF_systemd

ln -s '/usr/lib/systemd/system/discover-host.service' '/etc/systemd/system/multi-user.target.wants/discover-host.service'

##### Ovirt-stuff begins here #####

# make sure we don't autostart virbr0 on libvirtd startup
rm -f /etc/libvirt/qemu/networks/autostart/default.xml

# rhevh uses libvirtd upstart job, sysv initscript must not interfere
rm -f /etc/rc.d/init.d/libvirtd

# Remove the default logrotate daily cron job
# since we run it every 10 minutes instead.
rm -f /etc/cron.daily/logrotate

# root's bash profile
cat >> /root/.bashrc << \EOF_bashrc
# aliases used for the temporary
function mod_vi() {
  /bin/vi $@
  restorecon -v $@ >/dev/null 2>&1
}

function mod_yum() {
  if [ "$1" == "--force" ]; then
      echo $@ > /dev/null
      shift
      /usr/bin/yum $@
  else
      printf "\nUsing yum is not supported\n\n"
  fi
}

function mod_less() {
    cat $1 | less
}

alias ping='ping -c 3'
alias yum="mod_yum"
alias less="mod_less"
export MALLOC_CHECK_=1
export LVM_SUPPRESS_FD_WARNINGS=0
EOF_bashrc

# directories required in the image with the correct perms
# config persistance currently handles only regular files
mkdir -p /root/.ssh
chmod 700 /root/.ssh
mkdir -p /boot
mkdir -p /boot-kdump
mkdir -p /config
mkdir -p /data
mkdir -p /data2
mkdir -p /live
mkdir -p /liveos
mkdir -p /root/.uml
mkdir -p /var/cache/multipathd
touch /var/lib/random-seed
echo "/dev/HostVG/Config /config ext4 defaults,noauto,noatime 0 0" >> /etc/fstab

# Create wwids file to prevent an error on boot, rhbz #805570
mkdir -p /etc/multipath
touch /etc/multipath/wwids
chmod 0600 /etc/multipath/wwids

# prepare for STATE_MOUNT in rc.sysinit
augtool << \EOF_readonly-root
set /files/etc/sysconfig/readonly-root/STATE_LABEL CONFIG
set /files/etc/sysconfig/readonly-root/STATE_MOUNT /config
set /files/etc/sysconfig/readonly-root/READONLY yes
save
EOF_readonly-root

# comment out /etc/* entries in rwtab to prevent overlapping mounts
sed -i '/^files	\/etc*/ s/^/#/' /etc/rwtab
cat > /etc/rwtab.d/ovirt << \EOF_rwtab_ovirt
files	/etc
dirs	/var/lib/multipath
dirs	/var/lib/net-snmp
dirs    /var/lib/dnsmasq
files	/root/.ssh
dirs	/root/.uml
files	/var/cache/libvirt
files	/var/empty/sshd/etc/localtime
files	/var/lib/libvirt
files   /var/lib/multipath
files   /var/cache/multipathd
empty	/mnt
files	/boot
empty	/boot-kdump
empty	/cgroup
files	/var/lib/yum
files	/var/cache/yum
files	/usr/share/snmp/mibs
files   /var/lib/lldpad
EOF_rwtab_ovirt

# fix iSCSI/LVM startup issue
sed -i 's/node\.session\.initial_login_retry_max.*/node.session.initial_login_retry_max = 60/' /etc/iscsi/iscsid.conf

#lvm.conf should use /dev/mapper and /dev/sdX devices
# and not /dev/dm-X devices
sed -i 's/preferred_names = \[ "^\/dev\/mpath\/", "^\/dev\/mapper\/mpath", "^\/dev\/\[hs\]d" \]/preferred_names = \[ "^\/dev\/mapper", "^\/dev\/\[hsv\]d" \]/g' /etc/lvm/lvm.conf

# kdump configuration
augtool << \EOF_kdump
set /files/etc/sysconfig/kdump/KDUMP_BOOTDIR /boot-kdump
set /files/etc/sysconfig/kdump/MKDUMPRD_ARGS --allow-missing
save
EOF_kdump

# add admin user for configuration ui
useradd admin
usermod -G wheel admin
usermod -s /usr/libexec/ovirt-admin-shell admin
echo "%wheel	ALL=(ALL)	NOPASSWD: ALL" >> /etc/sudoers

# load modules required by crypto swap
cat > /etc/sysconfig/modules/swap-crypt.modules << \EOF_swap-crypt
#!/bin/sh

modprobe aes >/dev/null 2>&1
modprobe dm_mod >/dev/null 2>&1
modprobe dm_crypt >/dev/null 2>&1
modprobe cryptoloop >/dev/null 2>&1
modprobe cbc >/dev/null 2>&1
modprobe sha256 >/dev/null 2>&1

EOF_swap-crypt
chmod +x /etc/sysconfig/modules/swap-crypt.modules

#strip out all unncesssary locales
localedef --list-archive | grep -v -i -E 'en_US.utf8' |xargs localedef --delete-from-archive
mv /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
/usr/sbin/build-locale-archive

# use static RPC ports, to avoid collisions
augtool << \EOF_nfs
set /files/etc/sysconfig/nfs/RQUOTAD_PORT 875
set /files/etc/sysconfig/nfs/LOCKD_TCPPORT 32803
set /files/etc/sysconfig/nfs/LOCKD_UDPPORT 32769
set /files/etc/sysconfig/nfs/MOUNTD_PORT 892
set /files/etc/sysconfig/nfs/STATD_PORT 662
set /files/etc/sysconfig/nfs/STATD_OUTGOING_PORT 2020
save
EOF_nfs

# XXX someting is wrong with readonly-root and dracut
# see modules.d/95rootfs-block/mount-root.sh
sed -i "s/defaults,noatime/defaults,ro,noatime/g" /etc/fstab

#mount kernel debugfs
echo "debugfs /sys/kernel/debug debugfs auto 0 0" >> /etc/fstab

#symlink ovirt-node-setup into $PATH
ln -s /usr/bin/ovirt-node-setup /usr/sbin/setup


#set NETWORKING off by default
augtool << \EOF_NETWORKING
set /files/etc/sysconfig/network/NETWORKING no
save
EOF_NETWORKING

# disable yum repos by default
rm -f /tmp/yum.aug
for i in $(augtool match /files/etc/yum.repos.d/*/*/enabled 1); do
    echo "set $i 0" >> /tmp/yum.aug
done
if [ -f /tmp/yum.aug ]; then
    echo "save" >> /tmp/yum.aug
    augtool < /tmp/yum.aug
    rm -f /tmp/yum.aug
fi

# cleanup yum directories
rm -rf /var/lib/yum/*

