#!/bin/bash

set -eu
set -x
set -o pipefail

ifup eth1

# Set the DNS to the one provided
sed -i 's/search openstacklocal/&\nnameserver $DNS_IP/' /etc/resolv.conf
sed -i -e 's/^PEERDNS.*/PEERDNS="no"/' /etc/sysconfig/network-scripts/ifcfg-eth0

curl -O http://buildvm-devops.usersys.redhat.com/puddle/build/AtomicOpenShift/3.1/latest/RH7-RHAOS-3.1.repo
mv RH7-RHAOS-3.1.repo /etc/yum.repos.d/

# master and nodes
retry yum install -y deltarpm
retry yum -y update

# master
retry yum install -y git httpd-tools

# TODO; Docker 1.6.2-14 is now in the repos, just do `yum install docker` here
# Centos 7.1: We need docker >= 1.6.2
retry yum install -y docker
echo "INSECURE_REGISTRY='--insecure-registry 0.0.0.0/0'" >> /etc/sysconfig/docker
systemctl enable docker

# Install flannel >= 0.3
retry yum -y install https://kojipkgs.fedoraproject.org//packages/flannel/0.5.3/5.fc24/x86_64/flannel-0.5.3-5.fc24.x86_64.rpm

# Install openstack nova and cinder clients
yum install -y https://rdoproject.org/repos/rdo-release.rpm
yum install -y python-novaclient python-cinderclient

mv /usr/lib/systemd/system/docker-storage-setup.service /root
systemctl daemon-reload

retry yum -y install ansible

cd /root/
git clone https://github.com/openshift/origin.git
git clone "$OPENSHIFT_ANSIBLE_GIT_URL" openshift-ansible
cd openshift-ansible
git checkout "$OPENSHIFT_ANSIBLE_GIT_REV"

# NOTE: the first ansible run hangs during the "Start and enable iptables
# service" task. Doing it explicitly seems to fix that:
yum install -y iptables iptables-services
systemctl enable iptables
systemctl restart iptables

# NOTE: Ignore the known_hosts check/propmt for now:
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook --inventory /var/lib/ansible-inventory playbooks/byo/config.yml

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

sed -i 's/:\${version}/:latest/' /etc/origin/master/master-config.yaml
systemctl restart atomic-openshift-master

ansible -i /var/lib/ansible-inventory nodes  -a "sed -i 's/:\${version}/:latest/' /etc/origin/node/node-config.yaml"
ansible -i /var/lib/ansible-inventory nodes  -a "systemctl restart atomic-openshift-node"

ansible -i /var/lib/ansible-inventory nodes  -a "docker pull openshift3/ose-pod:latest"
ansible -i /var/lib/ansible-inventory nodes  -a "docker pull openshift3/ose-docker-registry:latest"
ansible -i /var/lib/ansible-inventory nodes  -a "docker pull openshift3/ose-haproxy-router:latest"

ansible -i /var/lib/ansible-inventory nodes  -a "docker pull openshift3/ose-deployer:latest"
ansible -i /var/lib/ansible-inventory nodes  -a "docker pull wordpress"
ansible -i /var/lib/ansible-inventory nodes  -a "docker pull openshift/mysql-55-centos7"

su root -c 'oadm manage-node "$(hostname)" --schedulable=true'

su root -c 'oadm manage-node "$(hostname)" --schedulable=true'

CA=/etc/origin/master
su root -c "oadm ca create-server-cert --signer-cert=$CA/ca.crt --signer-key=$CA/ca.key --signer-serial=$CA/ca.serial.txt --hostnames='*.cloudapps.$DOMAIN' --cert=cloudapps.crt --key=cloudapps.key"

cat cloudapps.crt cloudapps.key $CA/ca.crt > cloudapps.router.pem

su root -c "oadm router --replicas=1 --default-cert=cloudapps.router.pem --credentials=/etc/origin/master/openshift-router.kubeconfig --selector='region=infra' --service-account=router --images='openshift3/ose-${component}:latest'"

su root -c "oadm registry --create --config=/etc/origin/master/admin.kubeconfig --credentials=/etc/origin/master/openshift-registry.kubeconfig --selector='region=infra' --images='openshift3/ose-${component}:latest'"

sleep 60

su root -c 'oadm manage-node "$(hostname)" --schedulable=false'

htpasswd -b /etc/openshift/openshift-passwd admin admin
su root -c "oadm policy add-role-to-user cluster-admin admin"

echo "OpenShift has been installed."
