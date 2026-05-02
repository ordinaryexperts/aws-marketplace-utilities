#!/bin/bash -ex

echo "$(date): ### Starting ubuntu_2204_2404_preinstall.sh ###"

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
if [[ $(lsb_release -si) == "Ubuntu" && $(lsb_release -sr) == "24.04" ]]; then
    # Ubuntu 24.04 ships with pip 24.0, setuptools 68.1.2, packaging 24.0 via apt
    # These are recent enough - don't try to upgrade them (they can't be upgraded via pip)
    python3 -m pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz --break-system-packages
else
    # Ubuntu 22.04 can upgrade these packages normally
    python3 -m pip install --upgrade pip setuptools packaging
    python3 -m pip install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz
fi

# install aws cli
cd /tmp
if [ "$USE_GRAVITON" = true ]; then
  curl https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip -o awscliv2.zip
else
  curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
fi
unzip -o awscliv2.zip
./aws/install --update
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
    # cmake + golang-go are needed to build efs-utils' transitive dep
    # aws-lc-fips-sys: it builds the AWS LibCrypto FIPS module via CMake,
    # which in turn invokes Go for FIPS-validation tooling.
    apt-get -y install cmake git binutils golang-go pkg-config libssl-dev
    # Install Rust via rustup. Ubuntu 22.04's apt-shipped cargo is too old to
    # parse efs-utils' Cargo.lock (lockfile version 4 requires recent cargo).
    # Don't apt-install rustc/cargo — they'd shadow rustup's modern toolchain.
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --default-toolchain stable
    # Packer runs this script via `sudo -E`, so $HOME stays /home/ubuntu while
    # euid is root. rustup installs to $HOME/.cargo; sourcing /root/.bashrc as
    # this script previously did was the wrong file. Cover both possible
    # install dirs explicitly.
    export PATH="$HOME/.cargo/bin:/root/.cargo/bin:$PATH"
    git clone https://github.com/aws/efs-utils /tmp/efs-utils
    cd /tmp/efs-utils
    ./build-deb.sh
    # build-deb.sh doesn't propagate cargo's exit code reliably, so the script
    # has historically continued past failures and shipped AMIs without
    # mount.efs. Fail loudly here if the .deb wasn't produced.
    ls /tmp/efs-utils/build/amazon-efs-utils*.deb >/dev/null 2>&1 || { echo "ERROR: amazon-efs-utils .deb not produced by build-deb.sh"; exit 1; }
    apt-get install -y ./build/amazon-efs-utils*deb
    cd -
fi

# install RDS SSL CA for Aurora
mkdir -p /opt/aws/rds
cd /opt/aws/rds
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem
cd -

echo "$(date): ### Finished ubuntu_2204_2404_preinstall.sh ###"
