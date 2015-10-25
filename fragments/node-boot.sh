#!/bin/bash

set -eu
set -x
set -o pipefail

ifup eth1

# master and nodes
# Set the DNS to the one provided
sed -i 's/search openstacklocal/&\nnameserver $DNS_IP/' /etc/resolv.conf
sed -i -e 's/^PEERDNS.*/PEERDNS="no"/' /etc/sysconfig/network-scripts/ifcfg-eth0


curl -O http://buildvm-devops.usersys.redhat.com/puddle/build/AtomicOpenShift/3.1/latest/RH7-RHAOS-3.1.repo
mv RH7-RHAOS-3.1.repo /etc/yum.repos.d/

# master and nodes
retry yum install -y deltarpm
retry yum -y update

yum -y install https://kojipkgs.fedoraproject.org//packages/flannel/0.5.3/5.fc24/x86_64/flannel-0.5.3-5.fc24.x86_64.rpm
