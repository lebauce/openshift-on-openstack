#!/bin/bash

set -eu
set -x
set -o pipefail

ifup eth1

# Set the DNS to the one provided
sed -i 's/search openstacklocal/&\nnameserver $DNS_IP/' /etc/resolv.conf

# Restart openshift services on master
service flanneld restart || true
service docker restart || true
service origin-node restart || true
iptables -F

# Create router and registry
su root -c "oadm manage-node --schedulable=true openshift-master.example.com"
su root -c "oadm create-server-cert --signer-cert=/etc/origin/master/ca.crt --signer-key=/etc/origin/master/ca.key --signer-serial=/etc/origin/master/ca.serial.txt --hostnames='*.cloudapps.example.com' --cert=cloudapps.crt --key=cloudapps.key"
cat cloudapps.crt cloudapps.key /etc/origin/master/ca.crt > cloudapps.router.pem
su root -c "oadm router router --credentials=/etc/origin/master/openshift-router.kubeconfig --service-account=router"
su root -c "oadm registry --config=/etc/origin/master/admin.kubeconfig --credentials=/etc/origin/master/openshift-registry.kubeconfig"
su root -c "oadm manage-node --schedulable=false openshift-master.example.com"

# Enable external connectivity
iptables -I OS_FIREWALL_ALLOW -p tcp -m tcp --dport 1936 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Restart openshift services on nodes
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node1.example.com sudo service flanneld restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node1.example.com sudo service docker restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node1.example.com sudo service origin-node restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node1.example.com sudo iptables -F || true

ssh -o StrictHostKeyChecking=no cloud-user@openshift-node2.example.com sudo service flanneld restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node2.example.com sudo service docker restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node2.example.com sudo service origin-node restart || true
ssh -o StrictHostKeyChecking=no cloud-user@openshift-node2.example.com sudo iptables -F || true

# Format cinder volumes
mkfs.ext3 /dev/vdb
mkfs.ext3 /dev/vdc

# NFS setup
echo "/pv0001 *(rw,no_root_squash)" > /etc/exports
echo "/pv0002 *(rw,no_root_squash)" >> /etc/exports
mkdir /pv0001
mkdir /pv0002
chmod 777 /pv0001
chmod 777 /pv0002
service nfs start

git clone https://github.com/openshift/origin.git
cd origin/examples/wordpress

sed -i 's/localhost/openshift-master.example.com/' nfs/pv-1.yaml
sed -i 's/\/home\/data//' nfs/pv-1.yaml
sed -i 's/localhost/openshift-master.example.com/' nfs/pv-2.yaml
sed -i 's/\/home\/data//' nfs/pv-2.yaml

sed -i "s/<volume1 ID>/$OPENSHIFT_VOL1_ID/" cinder/pv-1.yaml
sed -i "s/<volume2 ID>/$OPENSHIFT_VOL2_ID/" cinder/pv-2.yaml

su root -c "oc export --raw=true scc/restricted > /origin/scc.yaml"
sed -i 's/MustRunAsRange/RunAsAny/' /origin/scc.yaml
su root -c "oc update scc/restricted -f /origin/scc.yaml"

su root -c "oc create -f /origin/examples/wordpress/nfs/pv-1.yaml"
su root -c "oc create -f /origin/examples/wordpress/nfs/pv-2.yaml"

# oc create -f cinder/pv-1.yaml
# oc create -f cinder/pv-2.yaml

su root -c "oc create -f /origin/examples/wordpress/pvc-wp.yaml"
su root -c "oc create -f /origin/examples/wordpress/pvc-mysql.yaml"

su root -c "oc create -f /origin/examples/wordpress/pod-mysql.yaml"
su root -c "oc create -f /origin/examples/wordpress/service-mysql.yaml"

su root -c "oc create -f /origin/examples/wordpress/pod-wordpress.yaml"
su root -c "oc create -f /origin/examples/wordpress/service-wp.yaml"

htpasswd -b /etc/openshift/openshift-passwd admin admin
su root -c "oadm policy add-role-to-user cluster-admin admin"

# master and nodes
# retry yum install -y deltarpm
# retry yum -y update

# master
# retry yum install -y git httpd-tools

# TODO; Docker 1.6.2-14 is now in the repos, just do `yum install docker` here
# Centos 7.1: We need docker >= 1.6.2
# retry yum install -y http://cbs.centos.org/kojifiles/packages/docker/1.6.2/4.gitc3ca5bb.el7/x86_64/docker-1.6.2-4.gitc3ca5bb.el7.x86_64.rpm
# echo "INSECURE_REGISTRY='--insecure-registry 0.0.0.0/0'" >> /etc/sysconfig/docker
# systemctl enable docker

# Install flannel >= 0.3
# retry yum -y install https://kojipkgs.fedoraproject.org//packages/flannel/0.5.3/5.fc24/x86_64/flannel-0.5.3-5.fc24.x86_64.rpm

# NOTE: install the right Ansible version on RHEL7.1 and Centos 7.1:
# retry yum -y install \
#     http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm
# sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
# retry yum -y --enablerepo=epel install ansible


# git clone "$OPENSHIFT_ANSIBLE_GIT_URL" openshift-ansible
# cd openshift-ansible
# git checkout "$OPENSHIFT_ANSIBLE_GIT_REV"

# NOTE: the first ansible run hangs during the "Start and enable iptables
# service" task. Doing it explicitly seems to fix that:
# yum install -y iptables iptables-services
# systemctl enable iptables
# systemctl restart iptables

# NOTE: Ignore the known_hosts check/propmt for now:
# export ANSIBLE_HOST_KEY_CHECKING=False
# ansible-playbook --inventory /var/lib/ansible-inventory playbooks/byo/config.yml

echo "OpenShift has been installed."
