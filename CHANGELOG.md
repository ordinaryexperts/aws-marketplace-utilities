# Unreleased

- Updated `UPGRADE.md` with field-tested additions from the 2.4.0 Mastodon release:
  - Prerequisites: explicit profile roles (dev/prod/test), devenv `:2.8.2` pin, `.gitignore` additions
  - Phase 3.1: AMI build runs in `oe-patterns-prod` (not dev)
  - Phase 5→7 restructure: don't merge/tag until Marketplace reports `SUCCEEDED`
  - Phase 6 Prerequisites: full `delivery_option:` block (required fields), role ARN guidance (`AWSMarketplaceAMIScanning`), example config
  - Phase 6 split across profiles (dev for publish, prod for validate/submit/status)
  - New Phase 7 covering final merge/tag, dev AMI for taskcat, Terraform module wrapper update
  - Troubleshooting: `IMAGE_ACCESS_EXCEPTION`, missing `delivery_option` fields, test account debt (expired cert, RDS snapshot quota, stuck CF stacks)
  - "Known upstream issues" section capturing bugs in `publish-template.sh`, `publish-diagram.sh`, `AwsMarketplaceAmiIngestion` role, and `marketplace.py validate`. Items 1, 3, 5 are now fixed (devenv `:2.8.2` / `:2.8.3`).
  - Pin recommendation updated to devenv `:2.8.3` (picks up both the validate logo fix and the config-driven publish scripts).

# 1.8.0

- Added `UPGRADE.md` — end-to-end upstream-version upgrade workflow for pattern repos.

# 1.7.5

* fixing ubuntu 24.04 pip

# 1.7.4

* fixing pip install commands

# 1.7.3

* update pip install commands

# 1.7.2

* add make clean-cdk and updated cdk related actions

# 1.7.1

* Save logs for AMI builds

# 1.7.0

* Adding session command for SSM Session
* Adding integration testing Make targets (test-integration, test-integration-ui, test-integration-all)

# 1.6.2

* Adding publish-diagram Make command

# 1.6.1

* Fix cfn bootstrap issue via pip upgrade

# 1.6.0

* Adding Ubuntu 24.04 support
* Dropping Ubuntu 20.04 support
* Adding plf-skip-pricing Make command
* Adding plf-skip-region Make command
* Adding plf-skip-pricing-and-region Make command

# 1.5.1

* Upgrading to Docker Compose V2

# 1.5.0

* Adding cargo to fix efs-utils install

# 1.4.0

* Integrating graviton preinstall script with main preinstall script

# 1.3.0

* Adding Ubuntu 20.04 preinstall
* Adding Ubuntu 20.04 support to postinstall

# 1.2.5

* Add more logging

# 1.2.4

* SSM Agent already installed on Ubuntu 22.04

# 1.2.3

* Add some logging

# 1.2.2

* Fix issue with pip3 symlink

# 1.2.1

* Remove 'set +u' from preinstall script
* Remove duplicate postinstall script

# 1.2.0

* Adding common packer templates
* Removing unused or migrated files

# 1.1.0

* Common Makefile commands

# 1.0.0

* Initial development
* PLF excel support
