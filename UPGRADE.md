# Upgrade Workflow

End-to-end guide for upgrading the upstream application version in an AWS Marketplace pattern repo.

Applies to any repo using `common.mk` from this repository (Mastodon, Discourse, Jitsi, Open WebUI, WordPress, Zulip, Pixelfed, PeerTube, BlueSky PDS, Plane, OpenHands, Rails, ConsulDemocracy, Atlantis, Devika, Backstage, SuiteCRM, Errbit, etc.).

## When to use this

Use this doc when the upstream project (e.g. mastodon/mastodon) has released a new version that you want to ship as a new release of the pattern.

Do NOT use this doc for:
- CDK library version bumps
- Infrastructure refactors unrelated to an upstream upgrade
- Bug fixes in the pattern code itself

## Prerequisites

- AWS profile configured. Typically `oe-patterns-dev` for testing: `export AWS_PROFILE=oe-patterns-dev`.
- Docker + docker-compose available (all `make` targets run through docker-compose).
- `gh` CLI authenticated: `gh auth status`.
- Pattern repo checked out.
- Working from a `feature/upgrade` branch (git-flow).

## Phases at a glance

1. **Research** — identify target version, diff dependencies
2. **Code changes** — bump version in packer script, validate locally
3. **AMI build** — build new AMI, update CDK `AMI_ID`
4. **Integration test** — run taskcat
5. **Release** — git-flow release, CHANGELOG, tag
6. **Marketplace submission** — submit new version via AWS Marketplace Catalog API

## Phase 1: Research

**Success criterion:** You have identified the target upstream version and reviewed its dependency diff against the currently-deployed version. No hard blockers (e.g., major runtime version bump requiring packer script changes) are unaddressed.

### 1.1 Find the current version

Look in the pattern repo's packer install script (typically `packer/ubuntu_2404_appinstall.sh`). The version is usually a variable near the top:

```bash
MASTODON_VERSION=4.5.6         # Mastodon
JITSI_VERSION=stable-10590     # Jitsi
OPEN_WEBUI_VERSION=0.6.43      # Open WebUI
WORDPRESS_VERSION=6.7.2        # WordPress
```

Discourse pins a git commit of `discourse_docker` plus a base image tag — see the `git checkout <sha>` and `discourse/base:<tag>` lines.

### 1.2 Find the latest upstream version

| Install method | Example repos | Version lookup |
|---|---|---|
| Source build (git + bundler/npm) | Mastodon | `gh release list --repo <owner>/<upstream>` |
| Docker base image | Discourse, Jitsi | Docker Hub tag list, or upstream release tags via `gh api repos/<u>/tags` |
| Pip package | Open WebUI | `pip index versions <package>` or PyPI release page |
| Direct download (ZIP/tar) | WordPress | Upstream release / downloads page |

Example:

```bash
gh release list --repo mastodon/mastodon --limit 10
```

### 1.3 Diff dependencies

For source-build repos, compare key dependency files between the old and new tags:

```bash
gh api repos/<owner>/<upstream>/compare/v<old>...v<new> \
  --jq '.files[] | select(.filename | test("^(\\.ruby-version|\\.nvmrc|Gemfile|Gemfile\\.lock|package\\.json|Dockerfile)$")) | .filename'
```

If `.ruby-version`, `.nvmrc`, or Dockerfile base images changed, the packer script probably needs updates beyond the version variable bump.

For Docker-based repos, compare the Dockerfile / compose file image tags in the upstream diff.

For pip packages, compare `requirements.txt` / `pyproject.toml` / `setup.py`.

For direct-download repos, read the upstream release notes and migration guide.

### 1.4 Read the upstream release notes

Always read the release notes between the current and target versions. Flag:
- Database migrations that require downtime or manual steps
- Breaking config changes (env vars removed/renamed)
- Minimum runtime version bumps (Ruby, Node, Python, PHP)
- Removed features you depend on

## Phase 2: Code changes

**Success criterion:** `make synth` and `make lint` both succeed with the new version in place. No CDK template errors.

### 2.1 Create a feature branch (if not already on one)

```bash
cd /path/to/pattern-repo
git checkout develop
git pull
git checkout -b feature/upgrade
```

### 2.2 Bump the version variable

Edit `packer/ubuntu_2404_appinstall.sh` (or `packer/ubuntu_2204_appinstall.sh` for older WordPress). Update the single version variable identified in Phase 1.

If Phase 1 found additional dependency changes:
- New Ruby version → update `RUBY_VERSION=`
- New Node major → update the `setup_XX.x` curl URL in the Node.js section
- New Python minor → update `PYTHON_VERSION=`
- New packer script version from this utilities repo → update `SCRIPT_VERSION=`

### 2.3 Local validation

```bash
make synth
make lint
```

Expected: synth writes `cdk.out/` without errors; lint reports no issues (or only pre-existing warnings).

If synth errors, the upstream change may have required a CDK code change. Investigate and fix before continuing.

## Phase 3: AMI build

**Success criterion:** Packer build exits 0. New AMI ID captured. `AMI_ID` constant in the CDK stack updated.

### 3.1 Build the AMI

```bash
AWS_PROFILE=oe-patterns-dev make ami-ec2-build TEMPLATE_VERSION=<new-version>
```

Typical duration: 20-40 minutes depending on the pattern.

Build output is also saved to `logs/ami-build-YYYYMMDD-HHMMSS.log` (see utilities repo README).

### 3.2 Capture the new AMI ID

The successful build prints lines like:

```
--> amazon-ebs: AMIs were created:
us-east-1: ami-0827c962454fe7bc0
```

Or at the bottom:

```
AMI_ID="ami-0827c962454fe7bc0"
```

### 3.3 Update the CDK stack

Edit `cdk/<app>/<app>_stack.py`. Find the `AMI_ID=` constant near the top:

```python
AMI_ID="ami-0827c962454fe7bc0" # ordinary-experts-patterns-<app>-<version>
```

Update both the ID and the trailing comment.

### 3.4 Verify synth still passes

```bash
make synth
```

Expected: clean synth with the new AMI ID.

## Phase 4: Integration test

**Success criterion:** `make test-main` completes with taskcat reporting `CREATE_COMPLETE` in all configured regions and no stack rollback.

### 4.1 Run taskcat

```bash
AWS_PROFILE=oe-patterns-dev make test-main
```

Typical duration: 20-40 minutes.

### 4.2 Interpret results

Search the output (or the taskcat log under `taskcat_outputs/`) for:

- `CREATE_COMPLETE` — stack deployed successfully
- `CREATE_FAILED` / `ROLLBACK_IN_PROGRESS` — stack failed; investigate
- `DELETE_COMPLETE` — taskcat cleaned up after itself

Example successful tail:

```
[INFO   ] : ┏ stack Ⓜ tCaT-<stack-name>
[INFO   ] : ┣ region: us-east-1
[INFO   ] : ┗ status: CREATE_COMPLETE
```

### 4.3 If tests fail

Most test failures manifest as EC2 user data script errors (the stack creates fine but instances fail to become healthy).

- Check CloudFormation events in the AWS console for the failure reason
- Check EC2 user data logs via the `debugging-ec2-user-data` skill — CloudWatch Logs group `/aws/ec2/<stack>` or SSM session on the instance
- Check `/var/log/cloud-init-output.log` on the instance for script errors

Common causes:
- Upstream app expects a newer runtime version that wasn't updated in the packer script
- Upstream config format changed; user_data.sh needs an update
- Network/IAM issue fetching secrets from Secrets Manager

### 4.4 Clean up failed tests

If taskcat leaves stacks or buckets behind:

```bash
make clean-snapshots-tcat
make clean-logs-tcat
make clean-buckets-tcat
```

### 4.5 Commit

```bash
git add packer/*.sh cdk/*/*_stack.py
git commit -m "feat: upgrade to <upstream> <new-version>"
git push -u origin feature/upgrade
```

## Phase 5: Release

**Success criterion:** Version tag pushed to origin. `CHANGELOG.md` updated and merged to `develop` and `main`.

This follows git-flow.

### 5.1 Open a PR from feature/upgrade → develop

Use `gh pr create` or the GitHub web UI. Get review, merge.

### 5.2 Start a release branch

```bash
git checkout develop
git pull
git checkout -b release/<new-pattern-version>
```

The pattern version is independent from the upstream version — it is the version of the CloudFormation template / Marketplace product (e.g. `2.4.0`). Bump major/minor/patch per semver of what changed.

### 5.3 Update CHANGELOG.md

Document the upgrade, breaking changes, and any manual migration steps users need to follow.

### 5.4 Finish the release

```bash
git commit -am "<pattern-version>"
git checkout main
git merge --no-ff release/<new-pattern-version>
git tag <new-pattern-version>
git checkout develop
git merge --no-ff release/<new-pattern-version>
git branch -d release/<new-pattern-version>
git push origin main develop <new-pattern-version>
```

## Phase 6: Marketplace submission

**Success criterion:** AWS Marketplace Catalog API changeset submitted and status transitions to `SUCCEEDED`. New version visible in the AWS Marketplace Management Portal.

This phase uses the AWS Marketplace Catalog API via `scripts/marketplace.py` (shipped in the devenv image). It replaces the older PLF spreadsheet workflow, the multi-region AMI copy step, and the separate template publish — the Catalog API handles region replication automatically and the submit command publishes the template for you.

### Prerequisites

- `marketplace_config.yaml` exists in the repo root. Required fields:
  - `product_id` — the AWS Marketplace product UUID (from the Management Portal)
  - `ami_access_role_arn` — IAM role that lets Marketplace read the AMI
  - `ami_parameter_pattern` — e.g. `AsgAmiIdv{version}` (version with dots stripped)
  - `template_bucket`, `template_pattern` — where the CFN template is published
  - `include_standalone_ami` — usually `false` for CFN-based products
  - OS metadata: `operating_system`, `operating_system_version`, `username`
  - `recommended_instance_type`, `usage_instructions`
- AWS credentials with `aws-marketplace:DescribeEntity` and `aws-marketplace:StartChangeSet` permissions.

### 6.1 Validate configuration

```bash
AWS_PROFILE=<your-profile> make marketplace-validate
```

Expected: confirms the product exists and required metadata is in place.

### 6.2 Submit the new version

```bash
AWS_PROFILE=<your-profile> make marketplace-submit \
  AMI_ID=<new-ami-id> \
  TEMPLATE_VERSION=<new-pattern-version>
```

This command:
1. Validates the CloudFormation template contains the expected AMI parameter
2. Publishes the template to S3 (`template_bucket`/`template_pattern`/`version`/template.yaml)
3. Parses release notes for `<new-pattern-version>` from `CHANGELOG.md`
4. Starts a Marketplace Catalog changeset

A changeset ID is written to `.marketplace_changeset` for later status checks.

### 6.3 Poll status until complete

```bash
AWS_PROFILE=<your-profile> make marketplace-status
```

(or pass `CHANGESET_ID=<id>` explicitly if `.marketplace_changeset` was cleared).

Expected terminal states:
- `SUCCEEDED` — version is live
- `FAILED` — see the error message in the status output; fix and re-submit

Typical duration: 15-45 minutes for review. The status command is safe to run repeatedly.

### 6.4 Verify in AWS Marketplace Management Portal

- Log in to the AWS Marketplace Management Portal
- Confirm the new version appears in the product's version list
- Confirm the CloudFormation template URL resolves and is the correct version
- Submit for AWS review if required by the product lifecycle

## Troubleshooting

### AMI build fails

**Symptoms:** `make ami-ec2-build` exits non-zero, Packer logs show provisioning errors.

- Missing system packages — upstream may have added a new dependency. Add to the `apt install` line in the packer script.
- Runtime version mismatch — upstream bumped Ruby/Node/Python. Update the version variable in the packer script (see Phase 1.3).
- Network timeout during `git clone` or `apt-get` — retry; if persistent, the upstream repo/package mirror may be down.
- Asset precompile OOM — increase Packer instance type in `packer/ami.json`.

### `make synth` errors

**Symptoms:** CDK throws during synthesis.

- CDK library mismatch — check `cdk/setup.py` for `oe-patterns-cdk-common` pin; upgrade if needed.
- Missing `CfnParameter` — the upstream upgrade may require a new configuration parameter. Add to the stack.
- Python import errors — run `make build` to rebuild the devenv container.

### Taskcat `CREATE_FAILED`

**Symptoms:** Stack creation fails during `make test-main`.

- EC2 instances fail health checks — most common. Investigate user_data execution:
  - CloudFormation console → Events tab on the failed stack
  - Use the `debugging-ec2-user-data` skill
  - SSM session into the instance, check `/var/log/cloud-init-output.log` and `/var/log/syslog`
- Secrets Manager access denied — IAM role change needed
- Database connection — Aurora may not be ready; check timeouts in user_data.sh

### Taskcat `DELETE_FAILED`

**Symptoms:** Taskcat cannot fully tear down resources after test.

- S3 bucket not empty — use the AWS console or CLI to empty then delete
- Snapshot retention — run `make clean-snapshots-tcat`
- Orphaned security groups / ENIs — manual cleanup in the AWS console

### AMI copy timeouts

**Symptoms:** `make ami-ec2-copy` hangs or fails in a specific region.

- EBS snapshot quota — check Service Quotas in the target region
- Cross-region bandwidth — retry the specific region
- Region not enabled on the account — enable or skip

### Reference: existing skills

- `debugging-ec2-user-data` — step-by-step EC2 boot failure investigation
- Pattern repo `CLAUDE.md` — project-specific context and conventions
