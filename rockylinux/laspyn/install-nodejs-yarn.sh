#!/bin/bash -e

NODEJS_VERSION=${NODEJS_VERSION:=10}

if [ -z "`rpm -qa nodejs`" ]; then
    echo Installing Node JS ${NODEJS_VERSION}
    sudo dnf -y module install nodejs:${NODEJS_VERSION}
    sudo dnf -y install nodejs
    node --version

    echo Configuring firewall...
    firewalld_status=`ps aux | grep firewall | grep -v grep | wc -l`
    sudo systemctl start firewalld
    echo Configuring firewall to allow traffic on port 3000...
    sudo firewall-cmd --zone=public --add-port=3000/tcp --permanent
    sudo firewall-cmd --reload
    if [ $firewalld_status -eq 0 ]; then
        sudo systemctl stop firewalld
    fi
fi

if [ -z "`rpm -qa yarn`" ]; then
    echo Installing yarn...
    curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | sudo tee /etc/yum.repos.d/yarn.repo
    sudo dnf -y install yarn
    yarn --version
fi

echo "$0 done!"
 