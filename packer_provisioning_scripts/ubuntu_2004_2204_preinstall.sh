#!/bin/bash -ex

echo "$(date): ### Starting ubuntu_2004_2204_preinstall.sh ###"

# parsing command line options
INSTALL_CODE_DEPLOY_AGENT=false
INSTALL_EFS_UTILS=false
USE_GRAVITON=false
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --install-code-deploy-agent)
        INSTALL_CODE_DEPLOY_AGENT=true
        shift
        ;;
        --install-efs-utils)
        INSTALL_EFS_UTILS=true
        shift
        ;;
        --use-graviton)
        USE_GRAVITON=true
        shift
        ;;
        *)
        echo "Unknown option: $key"
        exit 1
        ;;
    esac
done

# wait for cloud-init to be done
if [ ! "$IN_DOCKER" = true ]; then
    cloud-init status --wait
fi

# apt upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get -y update && apt-get -y upgrade

# install helpful utilities
apt-get -y install curl git jq ntp software-properties-common unzip vim wget zip xfsprogs

# install latest CFN utilities
apt-get -y install python3-pip
pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz

# install aws cli
cd /tmp
if [ "$USE_GRAVITON" = true ]; then
  curl https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip -o awscliv2.zip
else
  curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
fi
unzip awscliv2.zip
./aws/install
cd -

# install CloudWatch agent
cd /tmp
if [ "$USE_GRAVITON" = true ]; then
  curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb
else
  curl https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o amazon-cloudwatch-agent.deb
fi
dpkg -i -E ./amazon-cloudwatch-agent.deb
cd -
# collectd for metrics
apt-get -y install collectd

# install CodeDeploy agent - requires ruby
if [ "$INSTALL_CODE_DEPLOY_AGENT" = true ]; then
    apt-get -y install ruby
    cd /tmp
    curl https://aws-codedeploy-us-west-1.s3.us-west-1.amazonaws.com/latest/install -o install
    chmod +x ./install
    ./install auto
    cd -
fi

# install efs mount helper - requires git
if [ "$INSTALL_EFS_UTILS" = true ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y
    source /root/.bashrc
    apt-get -y install git binutils rustc cargo pkg-config libssl-dev
    git clone https://github.com/aws/efs-utils /tmp/efs-utils
    cd /tmp/efs-utils
    ./build-deb.sh
    apt-get install -y ./build/amazon-efs-utils*deb
    cd -
fi

# install RDS SSL CA for Aurora
mkdir -p /opt/aws/rds
cd /opt/aws/rds
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem
cd -

echo "$(date): ### Finished ubuntu_2004_2204_preinstall.sh ###"
