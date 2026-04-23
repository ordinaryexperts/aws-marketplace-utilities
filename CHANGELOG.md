# Unreleased

# 1.9.4

- scripts/marketplace_rebrand.py: new tool for FOSSonCloud rebrand — submits UpdateInformation + UpdateLogo change sets to the AWS Marketplace Catalog API driven by a `product_info:` block in the pattern repo's marketplace_config.yaml. Supports `--dry-run` for previewing change sets without AWS calls. Accompanying lib at scripts/marketplace_rebrand_lib.py with pytest unit tests at scripts/tests/test_marketplace_rebrand_lib.py.

# 1.9.3

- UPGRADE.md: added Phase 0 "Brand alignment check" — first-upgrade checklist to confirm pattern repo + live AWS Marketplace product use the "`<App> on AWS by FOSSonCloud`" style consistently.
- UPGRADE.md: restructured to 9 phases — split out "Phase 8: Upgrade the companion Terraform module" and "Phase 9: Generate marketing materials" as their own phases. Previously Phase 8 was a subsection (7.3) of Finalize release; marketing generation wasn't in the doc.
- UPGRADE.md: added Phase 2.3 note about `--break-system-packages` for pip3 install (Dockerfile must include this when bumping from devenv `<2.7.0` to `>=2.7.0` — Ubuntu 24.04 / PEP 668).
- UPGRADE.md: added Phase 2.4 recommendation to bump `aws-cdk-lib` and `oe-patterns-cdk-common` together, with a warning about Aurora 15.4→15.13 and Redis 6.2→7.0 migrations that come with `cdk-common 4.3.0+`.

# 1.9.2

- UPGRADE.md: added Phase 2.3.1 covering the versioned AMI parameter suffix convention (`NEXT_RELEASE_PREFIX`, `ami_id_param_name_suffix` on Asg, Makefile `AsgAmiIdvXXX` deploy param). Required for all patterns going forward; documents both "introduce new" and "bump existing" flows.
- UPGRADE.md: restructured Phase 3 to reflect dev-AMI-first workflow (previously had dev AMI as optional Phase 7.2). Phase 3 now builds dev AMI for testing; prod AMI build is Phase 6 prerequisite. Phase 7.2 restores dev AMI reference on develop branch post-release.
- UPGRADE.md: Phase 6 Prerequisites clarified — both UUID and `prod-*` product_id formats are supported.
- UPGRADE.md: restructured Phase 4 integration-test to canonical five-step flow: `make deploy` → `make test-integration` (playwright) → manual verification → `make destroy` → `make test-main` (taskcat). Notes patterns without `test/integration/` need to add basic playwright tests.

# 1.9.1

- UPGRADE.md: added Phase 4.1 callouts for (a) hardcoded stale VPC IDs in some older Makefile `deploy` targets (discourse had this) and (b) mandatory stack deletion after `CREATE_FAILED`/`ROLLBACK_COMPLETE` before retrying CDK deploy.
- UPGRADE.md: added new Phase 0 pointing to pattern-specific CLAUDE.md notes. Discourse CLAUDE.md now documents the two-place `discourse/base` pin (packer git checkout + docker pull in ubuntu_2404_appinstall.sh) and 40GB root volume minimum. Empirically confirmed that adding `base_image:` to `app.yml`'s top level causes launcher to fail with YAML syntax error, so the canonical fix is to pin `discourse_docker` commit + matching `docker pull`.
- Discourse CLAUDE.md: removed the legacy `web.ssl.template.yml` line-number sed (no longer needed — ALB uses HTTPS health checks so the HTTP redirect doesn't affect /srv/status; and upstream's nginx-outlets refactor in PR #959 moved the target lines so the sed corrupted YAML).
- `common.mk`: `destroy` target now passes `--force` to `cdk destroy` so it doesn't hang waiting for a confirmation prompt in non-TTY contexts (CI, backgrounded make).

# 1.9.0

- Updated UPGRADE.md

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
