#!/bin/bash

set -eu
set -x
set -o pipefail

function notify_success() {
    $WC_NOTIFY --data-binary  "{\"status\": \"SUCCESS\", \"reason\": \"$1\", \"data\": \"$1\"}"
    exit 0
}

function notify_failure() {
    $WC_NOTIFY --data-binary "{\"status\": \"FAILURE\", \"reason\": \"$1\", \"data\": \"$1\"}"
    exit 1
}

# master and nodes
# Set the DNS to the one provided
sed -i 's/search openstacklocal/&\nnameserver $DNS_IP/' /etc/resolv.conf
sed -i -e 's/^PEERDNS.*/PEERDNS="no"/' /etc/sysconfig/network-scripts/ifcfg-eth0

# cloud-init does not set the $HOME, which is used by ansible
export HOME=/root
cd $HOME

# master and nodes
retry yum install -y deltarpm || notify_failure "could not install deltarpm"
retry yum -y update || notify_failure "could not update RPMs"

# master
retry yum install -y git httpd-tools || notify_failure "could not install httpd-tools"

retry yum -y install docker || notify_failure "could not install docker"
echo "INSECURE_REGISTRY='--insecure-registry 0.0.0.0/0'" >> /etc/sysconfig/docker
systemctl enable docker

# Setup Docker Storage Volume Group
if ! [ -b /dev/vdb ]; then
  echo "ERROR: device /dev/vdb does not exist" >&2
  notify_failure "device /dev/vdb does not exist"
fi

systemctl enable lvm2-lvmetad
systemctl start lvm2-lvmetad
cat << EOF > /etc/sysconfig/docker-storage-setup
DEVS=/dev/vdb
VG=docker-vg
EOF

/usr/bin/docker-storage-setup

# NOTE: install the right Ansible version on RHEL7.1 and Centos 7.1:
if ! rpm -q epel-release-7-5;then
    retry yum -y install \
        http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm \
        || notify_failure "could not install EPEL"
fi
sed -i -e "s/^enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo
retry yum -y --enablerepo=epel install ansible pyOpenSSL || notify_failure "could not install ansible"

git clone "$OPENSHIFT_ANSIBLE_GIT_URL" openshift-ansible \
    || notify_failure "could not clone openshift-ansible"
cd openshift-ansible
git checkout "$OPENSHIFT_ANSIBLE_GIT_REV"

# NOTE: the first ansible run hangs during the "Start and enable iptables
# service" task. Doing it explicitly seems to fix that:
yum install -y iptables iptables-services || notify_failure "could not install iptables-services"
systemctl enable iptables
systemctl restart iptables

notify_success "OpenShift node has been prepared for running ansible."
