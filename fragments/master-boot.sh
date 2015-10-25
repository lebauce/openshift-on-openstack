#!/bin/bash

set -eu
set -x
set -o pipefail

ifup eth1

# Set the DNS to the one provided
sed -i 's/search openstacklocal/&\nnameserver $DNS_IP/' /etc/resolv.conf
sed -i -e 's/^PEERDNS.*/PEERDNS="no"/' /etc/sysconfig/network-scripts/ifcfg-eth0

# Remove nodes
su root -c "kubectl delete node openshift-master.example.com"
su root -c "kubectl delete node openshift-node-ooxey.example.com"
su root -c "kubectl delete node openshift-node-tfykn.example.com"

# Enable external connectivity
iptables -I OS_FIREWALL_ALLOW -p tcp -m tcp --dport 1936 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

python <<EOF
import yaml
conf = yaml.load(open("/etc/origin/master/master-config.yaml"))
conf['kubernetesMasterConfig']['controllerArguments'] = { 'cloud-provider': [ 'openstack' ], 'cloud-config': [ '/etc/cloud.conf' ] }
conf['kubernetesMasterConfig']['apiServerArguments'] = { 'cloud-provider': [ 'openstack' ], 'cloud-config': [ '/etc/cloud.conf' ] }
yaml.dump(conf, open("/etc/origin/master/master-config.yaml", "w"))
EOF

cat > node-config.yaml <<EOF
kubeletArguments:
  cloud-provider:
    - "openstack"
  cloud-config:
    - "/etc/cloud.conf"
EOF

cat node-config.yaml >> /etc/origin/node/node-config.yaml

# Restart openshift services on master
setenforce 0
service flanneld restart || true
service docker restart || true
service atomic-openshift-master restart || true
service atomic-openshift-node restart || true
iptables -F

# Restart openshift services on nodes
scp -o StrictHostKeyChecking=no node-config.yaml cloud-user@openshift-node-ooxey.example.com:/tmp
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo bash -c '"cat /tmp/node-config.yaml >> /etc/origin/node/node-config.yaml"'
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo setenforce 0 || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo service flanneld restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo service docker restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo service atomic-openshift-node restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-ooxey.example.com sudo iptables -F || true

scp -o StrictHostKeyChecking=no node-config.yaml cloud-user@openshift-node-tfykn.example.com:/tmp
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo bash -c '"cat /tmp/node-config.yaml >> /etc/origin/node/node-config.yaml"'
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo setenforce 0 || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo service flanneld restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo service docker restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo service atomic-openshift-node restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node-tfykn.example.com sudo iptables -F || true

export OS_AUTH_URL=`grep auth-url /etc/cloud.conf | cut -f 3 -d ' '`
export OS_USERNAME=`grep username /etc/cloud.conf | cut -f 3 -d ' '`
export OS_PASSWORD=`grep password /etc/cloud.conf | cut -f 3 -d ' '`
export OS_TENANT_ID=`grep tenant-id /etc/cloud.conf | cut -f 3 -d ' '`
export OS_REGION_NAME=`grep region /etc/cloud.conf | cut -f 3 -d ' '`

export OPENSHIFT_VOL1_ID=`cinder create --display-name pv0001 1 | grep ' id ' | cut -f 3 -d '|'`
export OPENSHIFT_VOL2_ID=`cinder create --display-name pv0002 5 | grep ' id ' | cut -f 3 -d '|'`

export MASTER_INSTANCE_ID=`python <<EOF
import urllib2
import json
response = urllib2.urlopen('http://169.254.169.254/openstack/latest/meta_data.json')
print json.load(response)['uuid']
EOF
`

nova volume-attach $MASTER_INSTANCE_ID $OPENSHIFT_VOL1_ID
nova volume-attach $MASTER_INSTANCE_ID $OPENSHIFT_VOL2_ID

sleep 10

# Format cinder volumes
mkfs.ext3 /dev/vdb
mkfs.ext3 /dev/vdc

mkdir /tmp/vol
mount /dev/vdb /tmp/vol
chmod 777 /tmp/vol
umount /dev/vdb

mount /dev/vdc /tmp/vol
chmod 777 /tmp/vol
umount /dev/vdc

nova volume-detach $MASTER_INSTANCE_ID $OPENSHIFT_VOL1_ID
nova volume-detach $MASTER_INSTANCE_ID $OPENSHIFT_VOL2_ID

su root -c "oc export --raw=true scc/restricted > scc.yaml"
sed -i 's/MustRunAsRange/RunAsAny/' scc.yaml
su root -c "oc update scc/restricted -f scc.yaml"

cd /root/origin/examples/wordpress

sed -i "s/<volume1 ID>/$OPENSHIFT_VOL1_ID/" cinder/pv-1.yaml
sed -i "s/<volume2 ID>/$OPENSHIFT_VOL2_ID/" cinder/pv-2.yaml

su root -c "oc create -f cinder/pv-1.yaml"
su root -c "oc create -f cinder/pv-2.yaml"

su root -c "oc create -f pvc-wp.yaml"
su root -c "oc create -f pvc-mysql.yaml"

su root -c "oc create -f pod-mysql.yaml"
su root -c "oc create -f service-mysql.yaml"

su root -c "oc create -f pod-wordpress.yaml"
su root -c "oc create -f service-wp.yaml"

echo "OpenShift has been installed."
