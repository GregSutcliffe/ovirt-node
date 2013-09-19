#!/bin/bash

# hacky build script which is basically all the steps from the
# Ovirt wiki instructions - GSS

export OVIRT_NODE_BASE=/root
export OVIRT_CACHE_DIR=~/ovirt-cache
export OVIRT_LOCAL_REPO=file://${OVIRT_CACHE_DIR}/ovirt
export EXTRA_RELEASE=.$USER$foremandiscovery

export LOGFILE=/tmp/build_`date '+%Y%m%d-%H%M'`.log
touch $LOGFILE

if [[ "$1" == "full" ]] ;then
  cd $OVIRT_NODE_BASE
  cd ovirt-node
  ./autogen.sh --with-image-minimizer 2>&1 | tee -a $LOGFILE
  make publish 2>&1 | tee -a $LOGFILE
fi

cd $OVIRT_NODE_BASE
cd ovirt-node-iso
./autogen.sh --with-recipe=/root/ovirt-node/recipe 2>&1 | tee -a $LOGFILE
REPO="http://yum.theforeman.org/nightly/f19/x86_64" make iso 2>&1 | tee -a $LOGFILE
rm -rf tftpboot
ln -snf ovirt*iso foreman.iso
livecd-iso-to-pxeboot foreman.iso 2>&1 | tee -a $LOGFILE
rm -f ovirt*iso
