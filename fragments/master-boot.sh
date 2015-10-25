#!/bin/bash

set -eu
set -x
set -o pipefail

ifup eth1

# Set the DNS to the one provided
sed -i 's/search openstacklocal/&\nnameserver $DNS_IP/' /etc/resolv.conf
sed -i -e 's/^PEERDNS.*/PEERDNS="no"/' /etc/sysconfig/network-scripts/ifcfg-eth0

# Restart openshift services on master
service flanneld restart || true
service docker restart || true
service atomic-openshift-node restart || true
iptables -F

# Enable external connectivity
iptables -I OS_FIREWALL_ALLOW -p tcp -m tcp --dport 1936 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Restart openshift services on nodes
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo service flanneld restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo service docker restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo service atomic-openshift-node restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo iptables -F || true

ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo service flanneld restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo service docker restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo service atomic-openshift-node restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo iptables -F || true

echo "OpenShift has been installed."
