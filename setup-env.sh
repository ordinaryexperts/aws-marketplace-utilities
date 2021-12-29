#!/usr/bin/env bash

echo "$(date): Starting setup-env.sh"

# system upgrades and tools
export DEBIAN_FRONTEND=noninteractive
apt-get -y -q update && apt-get -y -q upgrade
apt-get -y -q install \
        curl  \
        git   \
        groff \
        jq    \
        less  \
        unzip \
        vim   \
        wget

# python
apt-get -y -q install python3 python3-pip

# aws cli
cd /tmp
curl --silent --show-error https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip -q awscliv2.zip
./aws/install
cd -

# For scripts/pfl.py
pip3 install -q \
     awspricing \
     openpyxl   \
     pandas     \
     pystache   \
     pyyaml

echo "$(date): Finished setup-env.sh"
