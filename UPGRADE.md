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

- AWS profiles configured:
  - `oe-patterns-dev` (account `992593896645`) — for local testing (`make deploy`), taskcat, template publishing.
  - `oe-patterns-prod` (account `879777583535`) — for the Marketplace-destined AMI build, `marketplace-validate`, `marketplace-submit`, `marketplace-status`.
  - `oe-patterns-test` (account `343218188409`) — for `terraform test` on the companion `terraform-aws-marketplace-oe-patterns-*` repos.
- Docker + docker-compose available (all `make` targets run through docker-compose).
- `gh` CLI authenticated: `gh auth status`.
- Pattern repo checked out.
- Working from a `feature/upgrade` branch (git-flow).
- Pattern's `Dockerfile` pinned to `ordinaryexperts/aws-marketplace-patterns-devenv:2.8.3` **or newer**. Earlier images had a broken `marketplace-validate` logo check (`:2.8.2` fixed) and hardcoded the template bucket in publish scripts (`:2.8.3` fixed). Bump it on the feature/upgrade branch if needed.
- Pattern's `.gitignore` includes `logs/` and `.marketplace_changeset` (runtime artifacts generated during the upgrade). Add them if missing.

## Phases at a glance

1. **Research** — identify target version, diff dependencies
2. **Code changes** — bump version in packer script, validate locally
3. **AMI build (dev)** — build dev AMI for testing, update CDK `AMI_ID`
4. **Integration test** — `make deploy` → playwright → manual verify → `make destroy` → `make test-main` (taskcat)
5. **Pre-release** — release branch, CHANGELOG (do NOT merge/tag yet)
6. **Marketplace submission** — build prod AMI, submit new version via AWS Marketplace Catalog API; wait for SUCCEEDED
7. **Finalize release** — merge release branch, tag, push; restore dev AMI on `develop`
8. **Terraform module bump** — update companion `terraform-aws-marketplace-oe-patterns-<app>` module with new template URL; `terraform test`; release
9. **Refresh patterns dashboard** — update `ordinaryexperts/patterns-dashboard` so cross-pattern view picks up new versions, FOSS drift, and current subscriber/usage counts
10. **Marketing materials** — generate blog post, LinkedIn post, YouTube script drafts

**Why Phase 7 is separate from Phase 6:** If Marketplace submission fails after you've already merged the release branch and pushed the tag, you have to back out published commits. Keep the release branch open through Phase 6.

**Why Phases 8, 9, and 10 are separate from Phase 7:** The terraform module test (Phase 8) can surface test-environment issues (expired cert, snapshot quota) that would stall the main pattern release if bundled. The dashboard refresh (Phase 9) and marketing step (Phase 10) are post-shipping housekeeping that should always follow confirmed-live shipping.

## Phase 0: Read pattern-specific notes

Before starting, check the pattern's own `CLAUDE.md` for an "Upgrade Workflow" section or similar. Some patterns have pattern-specific gotchas that live there (image pinning conventions, root volume minimums, config file layouts, etc.) — they supplement this doc rather than duplicate it.

Examples:
- Discourse: `discourse/base` image must be pinned in `packer/ubuntu_2404_appinstall.sh` in **both** the `git checkout <sha>` of `discourse_docker` AND the `docker pull discourse/base:<version>` — both must reference the same image version. Needs 40GB root volume.
- Mastodon: uses `setup.py` + `-e .` in `requirements.txt` (not all patterns do).

### Brand alignment check (one-time per pattern)

The FOSSonCloud brand style for pattern products is **`<App Name> on AWS by FOSSonCloud`**. On the first upgrade of a pattern that hasn't been rebranded yet, confirm these match:

| Location | Target value |
|---|---|
| `README.md` heading | `<App Name> on AWS by FOSSonCloud` |
| `README.md` tagline | "A FOSSonCloud AWS Marketplace Product" |
| `marketplace_config.yaml` `delivery_option.short_description` | starts with "Deploy a production-ready `<App>`..." |
| `marketplace_config.yaml` `delivery_option.long_description` | opens with "`<App>` on AWS by FOSSonCloud..." |
| AWS Marketplace Management Portal product title | `<App Name> on AWS by FOSSonCloud` |
| `diagram.png` title | "`<App Name>` on AWS by FOSSonCloud — Architecture" |

If the live AWS Marketplace product title still uses the older "Ordinary Experts `<App>` Pattern" wording, update it via the Catalog API `UpdateInformation` change type (see Troubleshooting > "Updating product metadata" below) as a follow-up after the version submission completes. Running both changesets simultaneously is safe but a little noisy in the portal — typically one after the other is cleaner.

`plf_config.yaml` is deprecated (replaced by `marketplace_config.yaml`) but may still carry old branding in existing pattern repos. Low priority to update; flag for removal in a cleanup pass.

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

### 2.3 Update the pattern's `Dockerfile` (if bumping from devenv < 2.7.0)

devenv `:2.7.0` switched to Ubuntu 24.04 / Python 3.12, which enforces PEP 668 (externally-managed environment). The pattern's `Dockerfile` needs `--break-system-packages` on `pip3 install`:

```dockerfile
RUN pip3 install -r requirements.txt --break-system-packages
```

Without this, `make synth`/`make build` fails with `error: externally-managed-environment`.

Patterns have two dependency-management conventions — both are supported:

- **`-e .` + `setup.py`** (used by mastodon): `requirements.txt` has `-e .`; versions are pinned in `cdk/setup.py`. Dockerfile must `COPY ./cdk/setup.py /tmp/code/cdk/` before `pip3 install`.
- **Plain requirements** (used by discourse): `cdk/requirements.txt` pins `aws-cdk-lib==X` and `oe-patterns-cdk-common@git+https://...@TAG` directly. No `setup.py`.

When bumping `oe-patterns-cdk-common`, update the correct file for the pattern's convention.

### 2.3.1 Introduce versioned AMI parameter suffix (if not already present)

Going forward, all patterns should use a versioned CloudFormation parameter for the AMI (e.g. `AsgAmiIdv240` for version `2.4.0`, not bare `AsgAmiId`). This makes parameter names change with each release, so CloudFormation treats the AMI swap as a real parameter change and doesn't silently reuse the prior value. It also keeps each pattern version's stack-update story clean.

If the pattern already uses `AsgAmiIdvXXX` (mastodon as of 2.3.0+), just bump the suffix to the new version:

1. Edit `cdk/<app>/<app>_stack.py`:
   ```python
   AMI_ID = "ami-<current>"  # will be updated in Phase 3
   NEXT_RELEASE_PREFIX = "v240"  # bump to new version, dots stripped
   ```
2. Ensure the `Asg()` call passes `ami_id_param_name_suffix=NEXT_RELEASE_PREFIX`.
3. Update the `Makefile` `deploy` target parameter name: `--parameters AsgAmiIdv240=ami-...`.

If the pattern still uses bare `AsgAmiId` (older patterns like discourse pre-1.2.0), introduce the convention:

1. In `cdk/<app>/<app>_stack.py`, add `NEXT_RELEASE_PREFIX = "v120"` right under the `AMI_ID` constant.
2. Add `ami_id_param_name_suffix=NEXT_RELEASE_PREFIX` to the `Asg(...)` construct call.
3. Rename the `Makefile` deploy parameter: `AsgAmiId` → `AsgAmiIdv120`.
4. In `marketplace_config.yaml`, set `ami_parameter_pattern: "AsgAmiIdv{version}"`.

Requires `oe-patterns-cdk-common >= 4.2.6` (first version with `ami_id_param_name_suffix` arg on `Asg`). If the pattern is on an older common library, Phase 2.4 bumps it.

### 2.4 Bump library versions (recommended)

When jumping across several devenv major versions, also bump the CDK and common-library pins to match the latest known-good combination. As of this writing, the mastodon 2.4.0 release uses:

```
aws-cdk-lib==2.225.0
oe-patterns-cdk-common@4.5.0
```

If you're bumping `oe-patterns-cdk-common` across `4.3.0`, Aurora PostgreSQL is auto-upgraded (15.4 → 15.13, **causes downtime on existing deployments**) and ElastiCache Redis is upgraded (6.2 → 7.0). Note these in CHANGELOG and communicate to users.

### 2.5 Local validation

```bash
make synth
make lint
```

Expected: synth writes `cdk.out/` without errors; lint reports no issues (or only pre-existing warnings).

If synth errors, the upstream change may have required a CDK code change. Investigate and fix before continuing.

## Phase 3: AMI build

**Success criterion:** Packer build(s) exit 0. New AMI ID captured. `AMI_ID` constant in the CDK stack updated.

Two AMI builds are needed over the full release cycle:

- **Dev AMI** (this phase) — for Phase 4 taskcat/local-deploy testing. Builds under `oe-patterns-dev`.
- **Prod AMI** (Phase 6 prerequisite) — for AWS Marketplace ingestion. Builds under `oe-patterns-prod`.

Building dev first catches pattern/infrastructure bugs before spending the 20-40 min on a second build and before touching Marketplace.

### 3.1 Build the dev AMI (for testing)

```bash
AWS_PROFILE=oe-patterns-dev make ami-ec2-build TEMPLATE_VERSION=<new-version>
```

Typical duration: 20-40 minutes depending on the pattern (Discourse is slower because it pulls the full `discourse/base` image).

Build output is also saved to `logs/ami-build-YYYYMMDD-HHMMSS.log` (add `logs/` to `.gitignore` if it isn't already).

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

### 3.3 Update the CDK stack and Makefile with the dev AMI

Edit `cdk/<app>/<app>_stack.py`:

```python
AMI_ID = "ami-<new-dev-ami>"  # ordinary-experts-patterns-<app>-<version>-...
```

Edit `Makefile` `deploy` target to reference the same AMI via the versioned parameter name from Phase 2.3.1:

```make
--parameters AsgAmiIdv240=ami-<new-dev-ami>
```

### 3.4 Verify synth still passes

```bash
make synth
```

Expected: clean synth with the new AMI ID.

> **Note:** The prod AMI build happens later, as a Phase 6 prerequisite. Same packer invocation, different profile — and you'll re-update `AMI_ID` to the prod AMI before `marketplace-submit`.

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

**Success criterion:** Dev stack deploys successfully, basic smoke tests pass, manual verification approved, then `make test-main` taskcat run completes with `CREATE_COMPLETE` in all regions.

This phase has five sub-steps, in order:

1. `make deploy` to dev account (single interactive stack, ~20-30 min)
2. Run playwright smoke tests against that stack
3. Notify user to manually verify the running site
4. On approval, `make destroy` to tear down
5. `make test-main` (taskcat) as the final multi-region regression check

### 4.1 Deploy the single dev stack

```bash
AWS_PROFILE=oe-patterns-dev make deploy
```

Deploys to `<app>-${USER}.dev.patterns.ordinaryexperts.com` using the hardcoded parameters in the `Makefile` `deploy` target (cert, DNS zone, admin email, etc.). Uses the dev AMI from Phase 3.

Typical duration: 20-30 minutes.

> **VPC parameter hygiene.** Some older pattern Makefiles hardcode `VpcId` / `VpcPrivateSubnet*Id` / `VpcPublicSubnet*Id` in the `deploy` target pointing at a specific dev-account VPC that no longer exists. If the deploy fails with `vpc ID 'vpc-...' does not exist`, either:
> - **Remove those parameters** from the Makefile (lets the CDK stack create a fresh VPC — the common approach, used by mastodon), or
> - Update the IDs to a VPC that currently exists in the dev account.
> 
> Creating a fresh VPC adds NAT Gateway cost for the duration of the test but avoids this failure mode entirely and matches what taskcat does.

> **Retry after CREATE_FAILED.** CloudFormation leaves the failed stack in `ROLLBACK_COMPLETE`. CDK will refuse to re-deploy until it's deleted: `aws cloudformation delete-stack --stack-name <app>-${USER}` then re-run `make deploy`.

### 4.2 Run basic playwright smoke tests

```bash
AWS_PROFILE=oe-patterns-dev make test-integration
```

The `test-integration` target runs pytest + playwright against the deployed dev site (see `test/integration/`). Each pattern should have at minimum:
- Home page loads over HTTPS
- Expected title / branding renders
- Auth / login entry point is present
- Any pattern-specific API healthcheck returns 200

**Patterns without `test/integration/`:** add basic playwright tests during the upgrade. See `aws-marketplace-oe-patterns-mastodon/test/integration/` for the conventional structure. If you don't add them this release, note it as a follow-up and skip to 4.3.

### 4.3 Manual verification

Report the deployed URL to the user and pause for approval:

- Open the site in a browser and confirm it renders correctly.
- Register the initial admin account (per `usage_instructions` in `marketplace_config.yaml`).
- Walk through the primary user flow (post a toot, start a meeting, open a forum topic, etc.).
- Check for regressions against the prior version's key features.

Do not proceed to 4.4 without explicit user approval.

### 4.4 Destroy the dev stack

```bash
AWS_PROFILE=oe-patterns-dev make destroy
```

Tears down VPC, Aurora, Redis, ALB, ASG, EFS, S3, Route53 records. Some resources (S3 buckets with objects, log groups) may have `RETAIN` deletion policies — clean those up manually if needed. Verify with `aws cloudformation describe-stacks` that no `<app>-${USER}` stack remains.

### 4.5 Run taskcat as the final regression check

```bash
AWS_PROFILE=oe-patterns-dev make test-main
```

Taskcat deploys in parallel across configured regions and auto-destroys. Typical duration: 20-40 minutes.

Interpret results — search the output (or the taskcat log under `taskcat_outputs/`) for:

- `CREATE_COMPLETE` — stack deployed successfully
- `CREATE_FAILED` / `ROLLBACK_IN_PROGRESS` — stack failed; investigate
- `DELETE_COMPLETE` — taskcat cleaned up after itself

Example successful tail:

```
[INFO   ] : ┏ stack Ⓜ tCaT-<stack-name>
[INFO   ] : ┣ region: us-east-1
[INFO   ] : ┗ status: CREATE_COMPLETE
```

### 4.6 If any step fails

Most failures manifest as EC2 user data script errors (the stack creates fine but instances fail to become healthy).

- Check CloudFormation events in the AWS console for the failure reason
- Check EC2 user data logs via the `debugging-ec2-user-data` skill — CloudWatch Logs group `/aws/ec2/<stack>` or SSM session on the instance
- Check `/var/log/cloud-init-output.log` on the instance for script errors

Common causes:
- Upstream app expects a newer runtime version that wasn't updated in the packer script
- Upstream config format changed; user_data.sh needs an update
- Network/IAM issue fetching secrets from Secrets Manager

If taskcat leaves stacks or buckets behind:

```bash
make clean-snapshots-tcat
make clean-logs-tcat
make clean-buckets-tcat
```

### 4.7 Commit

```bash
git add packer/*.sh cdk/*/*_stack.py
git commit -m "feat: upgrade to <upstream> <new-version>"
git push -u origin feature/upgrade
```

## Phase 5: Pre-release

**Success criterion:** Release branch exists on origin with the version bump + CHANGELOG entry committed. **Do not merge to main or tag yet** — that happens in Phase 7, after Marketplace submission succeeds.

This follows git-flow, but split across two phases.

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

### 5.4 Commit to the release branch

```bash
git commit -am "<pattern-version>"
git push -u origin release/<new-pattern-version>
```

**Stop here.** Do NOT merge to `main`, do NOT tag yet. Proceed to Phase 6. If Marketplace submission fails, you can fix issues on the release branch without having published broken commits. Phase 7 finalizes the release once Marketplace reports SUCCEEDED.

## Phase 6: Marketplace submission

**Success criterion:** AWS Marketplace Catalog API changeset submitted and status transitions to `SUCCEEDED`. New version visible in the AWS Marketplace Management Portal.

This phase uses the AWS Marketplace Catalog API via `scripts/marketplace.py` (shipped in the devenv image). It replaces the older PLF spreadsheet workflow, the multi-region AMI copy step, and the separate template publish — the Catalog API handles region replication automatically and the submit command publishes the template for you.

### Prerequisites

- **Prod AMI built** — run `AWS_PROFILE=oe-patterns-prod make ami-ec2-build TEMPLATE_VERSION=<version>` (same packer invocation as Phase 3.1, different profile). The Marketplace ingestion role only reads AMIs from the prod account. Update `AMI_ID` in `cdk/<app>/<app>_stack.py` to the new prod AMI ID before running `marketplace-submit` in 6.2.
- `marketplace_config.yaml` exists in the repo root. Required fields:
  - `product_id` — the AWS Marketplace product identifier (from the Management Portal). Older products use UUID format (e.g. `d0a98067-9a26-440a-858e-00193a953934`), newer products use the `prod-*` format (e.g. `prod-xytpfnlptgpg6`). Both work with `marketplace.py`.
  - `ami_access_role_arn` — IAM role that lets Marketplace read the AMI. **Use `arn:aws:iam::879777583535:role/AWSMarketplaceAMIScanning`** — this is the role with the AWS-managed `AWSMarketplaceAmiIngestion` policy attached. Do **not** use `arn:aws:iam::879777583535:role/AwsMarketplaceAmiIngestion`; its inline policy is incomplete and causes `IMAGE_ACCESS_EXCEPTION`.
  - `ami_parameter_pattern` — e.g. `AsgAmiIdv{version}` (version with dots stripped)
  - `template_bucket`, `template_pattern` — where the CFN template is published. See "Known upstream issue" below: `template_bucket` is currently ignored by `publish-template.sh` — the hardcoded value `ordinary-experts-aws-marketplace-pattern-artifacts` is used.
  - `include_standalone_ami` — usually `false` for CFN-based products
  - OS metadata: `operating_system`, `operating_system_version`, `username`
  - `recommended_instance_type`, `usage_instructions`
  - **`delivery_option:` block** (required — `marketplace-submit` errors out without it):
    - `short_description` — one-line summary of what the CloudFormation template deploys
    - `long_description` — detailed description of deployed resources and requirements
    - `architecture_diagram_url` — publicly-reachable URL to the architecture diagram (e.g. `https://ordinary-experts-aws-marketplace-pattern-artifacts.s3.amazonaws.com/<pattern>/<version>/diagram.png` after `make publish-diagram`)
- AWS credentials with `aws-marketplace:DescribeEntity` and `aws-marketplace:StartChangeSet` permissions.
- Product metadata in the AWS Marketplace Management Portal: product title, short/long description, logo (via PromotionalResources), highlights, support description. `make marketplace-validate` reports any missing fields.

#### Example `marketplace_config.yaml`

```yaml
product_id: "<uuid-from-management-portal>"

ami_access_role_arn: "arn:aws:iam::879777583535:role/AWSMarketplaceAMIScanning"

ami_parameter_pattern: "AsgAmiIdv{version}"

template_bucket: "ordinary-experts-aws-marketplace-pattern-artifacts"
template_pattern: "<pattern-name>"  # e.g. "mastodon"

include_standalone_ami: false

operating_system: "UBUNTU"
operating_system_version: "24.04"
username: "ubuntu"
recommended_instance_type: "m5.xlarge"

usage_instructions: >-
  Run the stack, providing valid parameters. When the stack creation completes,
  go to the outputs of the stack and open the URL in your browser. ...

delivery_option:
  short_description: |
    Deploy <app> on AWS with this CloudFormation template and custom AMI. ...
  long_description: |
    <app> on AWS by FOSSonCloud deploys ...

    WHAT'S DEPLOYED

    - VPC with public and private subnets (or use existing)
    - ...

    REQUIREMENTS

    - Route 53 hosted zone for DNS
    - ACM certificate for HTTPS
  architecture_diagram_url: "https://ordinary-experts-aws-marketplace-pattern-artifacts.s3.amazonaws.com/<pattern>/<version>/diagram.png"
```

#### Profile pairing for Phase 6

The template bucket lives in `oe-patterns-dev` (account `992593896645`); the Marketplace ingestion role lives in `oe-patterns-prod` (account `879777583535`). Phase 6 is split across profiles:

| Step | Target | Profile |
|---|---|---|
| 6.1 Validate product metadata | `make marketplace-validate` | `oe-patterns-prod` |
| 6.1.1 Publish template | `make publish TEMPLATE_VERSION=<v>` | `oe-patterns-dev` |
| 6.1.2 Publish diagram | `make publish-diagram TEMPLATE_VERSION=<v>` | `oe-patterns-dev` |
| 6.2 Submit version to Marketplace | `make marketplace-submit AMI_ID=<id> TEMPLATE_VERSION=<v>` | `oe-patterns-prod` |
| 6.3 Poll status | `make marketplace-status` | `oe-patterns-prod` |

> **Note:** `make marketplace-submit` internally re-runs the template publish step. If the template was already published under `oe-patterns-dev` in 6.1.1, the internal re-publish under the prod profile may fail with S3 `AccessDenied` in the future — currently it happens to succeed because of account-specific IAM grants. File an upstream issue if this bites you. The safe workaround is to make sure Phase 6.1.1 has succeeded before Phase 6.2 runs; the submit step can then use the already-published template if needed.

### 6.1 Validate product metadata

```bash
AWS_PROFILE=oe-patterns-prod make marketplace-validate
```

Expected: confirms the product exists and required metadata (title, descriptions, logo, highlights, support description) is in place. If any field is missing, fill it in via the AWS Marketplace Management Portal before proceeding.

> **Requires devenv image `:2.8.2` or newer.** Earlier images checked the logo URL in the wrong place on the entity (`Description.LogoUrl` instead of `PromotionalResources.LogoUrl`) and emitted a false-positive failure.

### 6.1.1 Publish the CloudFormation template

```bash
AWS_PROFILE=oe-patterns-dev make publish TEMPLATE_VERSION=<new-pattern-version>
```

Uploads `dist/template.yaml` to `s3://ordinary-experts-aws-marketplace-pattern-artifacts/<pattern>/<version>/template.yaml` with `--acl public-read` so AWS Marketplace can fetch it.

Verify the URL responds: `curl -sI https://ordinary-experts-aws-marketplace-pattern-artifacts.s3.amazonaws.com/<pattern>/<version>/template.yaml` should be `HTTP/1.1 200 OK`.

### 6.1.2 Publish the architecture diagram (if `delivery_option.architecture_diagram_url` points to S3)

```bash
AWS_PROFILE=oe-patterns-dev make publish-diagram TEMPLATE_VERSION=<new-pattern-version>
```

Same bucket, `<pattern>/<version>/diagram.png` path.

### 6.2 Submit the new version

```bash
AWS_PROFILE=oe-patterns-prod make marketplace-submit \
  AMI_ID=<new-ami-id> \
  TEMPLATE_VERSION=<new-pattern-version>
```

This command:
1. Validates the CloudFormation template contains the expected AMI parameter
2. Re-publishes the template to S3 (may be a no-op if 6.1.1 already did it)
3. Parses release notes for `<new-pattern-version>` from `CHANGELOG.md`
4. Starts a Marketplace Catalog changeset

A changeset ID is written to `.marketplace_changeset` for later status checks.

### 6.3 Poll status until complete

```bash
AWS_PROFILE=oe-patterns-prod make marketplace-status
```

(or pass `CHANGESET_ID=<id>` explicitly if `.marketplace_changeset` was cleared).

Expected terminal states:
- `SUCCEEDED` — version is live on AWS Marketplace. **Proceed to Phase 7.**
- `FAILED` — see the error message. Common failures: `IMAGE_ACCESS_EXCEPTION` (see Troubleshooting), wrong AMI parameter name in template. Fix and re-submit from 6.2; the previous failed changeset does not block retry.

Typical duration: 15-45 minutes for review. The status command is safe to run repeatedly; set up a polling watcher if you're stepping away.

### 6.4 Verify in AWS Marketplace Management Portal

- Log in to the AWS Marketplace Management Portal
- Confirm the new version appears in the product's version list
- Confirm the CloudFormation template URL resolves and is the correct version
- Submit for AWS review if required by the product lifecycle

## Phase 7: Finalize release

**Success criterion:** Release branch merged, tag pushed, companion repos (terraform wrapper) updated.

Only run this phase AFTER Phase 6.3 reports `SUCCEEDED`. Running it earlier risks leaving a tagged commit in `main` that references a Marketplace submission that doesn't exist.

### 7.1 Merge and tag

```bash
git checkout main
git pull
git merge --no-ff release/<new-pattern-version>
git tag <new-pattern-version>
git checkout develop
git pull
git merge --no-ff release/<new-pattern-version>
git branch -d release/<new-pattern-version>
git push origin main develop <new-pattern-version>
```

### 7.2 Restore the dev AMI reference for taskcat

CI runs weekly taskcat tests against the AMI referenced in `cdk/<app>/<app>_stack.py`. If the stack is left pointing at the **prod** AMI used for Marketplace submission, taskcat (running in `oe-patterns-dev`) cannot find it. Put the dev AMI ID from Phase 3 back into the stack on `develop`:

```bash
git checkout develop
# Edit cdk/<app>/<app>_stack.py: AMI_ID = "<dev-ami-id-from-phase-3.2>"
git commit -am "Restore dev AMI reference for post-<new-version> taskcat"
git push origin develop
```

Alternative: if the dev AMI is stale (older than the prod AMI built in Phase 6 prerequisites), run `AWS_PROFILE=oe-patterns-dev make ami-ec2-build` again to refresh.

(Multi-region `make ami-ec2-copy` is no longer needed — taskcat runs in us-east-1 and the Marketplace Catalog API handles multi-region replication of the prod AMI automatically.)

## Phase 8: Upgrade the companion Terraform module

**Success criterion:** `terraform-aws-marketplace-oe-patterns-<app>` module points at the new Marketplace-hosted template URL, passes `terraform test` against the `oe-patterns-test` account, and is tagged with the same version as the pattern release.

Pattern repos that have a companion `terraform-aws-marketplace-oe-patterns-<app>` module (Mastodon, Discourse, and others) wrap the Marketplace CloudFormation template in a Terraform module so users who prefer Terraform can deploy the pattern. The module must be bumped after each pattern release so its `template_url` resolves to the new version's AWS-hosted template.

### 8.1 Get the new AWS-hosted template URL

After Phase 6 succeeds, the Marketplace Catalog API exposes the template URL at the new version:

```bash
AWS_PROFILE=oe-patterns-prod aws marketplace-catalog describe-entity \
  --region us-east-1 --catalog AWSMarketplace \
  --entity-id <product-id> --query "Details" --output text \
  | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); v=[x for x in d['Versions'] if x['VersionTitle']=='<new-version>'][0]; s=[x for x in v['Sources'] if x['Type']=='CloudFormationTemplate'][0]; print(s['Template'])"
```

The URL looks like `https://awsmp-cft-211125678794-1707910187780.s3.us-east-1.amazonaws.com/<uuid>/<uuid>/template.yaml`. Verify it returns HTTP 200 (`curl -sI <url>`).

### 8.2 Update the module

In the terraform module repo:

1. Edit `main.tf` — swap `template_url =` to the new URL.
2. Edit `CHANGELOG.md` — add an entry for the new version (usually matches the pattern version).

### 8.3 Validate and test

```bash
cd /path/to/terraform-aws-marketplace-oe-patterns-<app>
AWS_PROFILE=oe-patterns-test terraform init
AWS_PROFILE=oe-patterns-test terraform fmt -check
AWS_PROFILE=oe-patterns-test terraform validate
AWS_PROFILE=oe-patterns-test terraform test -verbose
```

`terraform test` actually deploys the stack to the `oe-patterns-test` account (~20-40 min). See the troubleshooting section for common test-account issues (expired cert, RDS snapshot quota, stuck CF stacks).

### 8.4 Release the module

Follow the same git-flow as the pattern repo:

```bash
git flow release start <new-version>
git commit -am "<new-version>"
git flow release finish <new-version>
git push origin main develop <new-version>
```

## Phase 9: Refresh the patterns dashboard

**Success criterion:** `ordinaryexperts/patterns-dashboard` reflects the new pattern version, the FOSS version it ships, the new TF module version, and current subscriber/usage counts.

The dashboard at `ordinaryexperts/patterns-dashboard` is the cross-pattern source of truth (replaces the old Google Sheet). Most fields are auto-derived from the pattern repos and AWS Marketplace data feeds, but a few patterns require a manual edit per release.

### 9.1 Manual edits (only some patterns)

Open `patterns.yml` in the dashboard repo. For the pattern you just shipped, update any manual fields that changed:

- **`mp_foss_version_override`** — set this if the pattern's packer script doesn't pin the FOSS version as a `*_VERSION=` env var (Discourse, Drupal, Consul Democracy fall into this bucket). Set it to the FOSS version that ships in the new MP release. If your pattern uses `mp_foss_version_var` (Mastodon, Pixelfed, Jitsi, Zulip, Bluesky PDS, WordPress, PeerTube, Open WebUI), the script reads it from the packer script automatically — no manual edit needed.
- **`status`** — flip `legacy → active` if a pattern coming back into active maintenance is being released; flip `active → legacy` if this is the final release.
- **`notes`** — only if a release-relevant gotcha changed.

Do NOT hand-edit auto-derived fields (`mp_version`, `mp_release_date`, `tf_module_version`, `active_subscribers`, `running_subscribers`, etc.) — they get clobbered on the next refresh.

### 9.2 Run the refresh

```bash
cd /path/to/patterns-dashboard
python3 scripts/refresh-patterns.py --aws
```

The script:
- Re-reads each pattern's `CHANGELOG.md` for the latest `mp_version` and `mp_release_date` (uses the version's git tag date when CHANGELOG has no inline date).
- Re-reads each `packer/ubuntu_*_appinstall.sh` for the FOSS version pin (`mp_foss_version_var`).
- Queries upstream GitHub releases (or PyPI for Open WebUI) for `foss_latest_version` — falls back to highest semver-shaped tag for repos that don't publish Releases (WordPress, Drupal, Bluesky PDS).
- Re-reads sibling `terraform-aws-marketplace-oe-patterns-<slug>/CHANGELOG.md` for `tf_module_version`.
- Walks `s3://aws-marketplace-data-feeds-delivery-resources-oe-us-east-1/` (default profile `oe-patterns-prod`; override with `--aws-profile`) to count distinct ACTIVE agreements per `marketplace_product_id` (`active_subscribers`) and distinct agreements with usage in the last 30 days (`running_subscribers`).
- Regenerates `PATTERNS.md` with a Health column (🔴/🟡/🟢/⚪) and the per-pattern detail sections.

GitHub API rate limit: the script falls back to `gh auth token` if `GITHUB_TOKEN` isn't set, so no extra config needed when `gh` is logged in.

### 9.3 Commit and push

```bash
git diff patterns.yml PATTERNS.md   # sanity check
git add patterns.yml PATTERNS.md
git commit -m "Refresh after <pattern> <new-version>"
git push origin main
```

If something looks wrong (e.g. the script picked up a pre-release tag as `foss_latest_version`), fix the relevant manual field in `patterns.yml`, re-run, then commit.

## Phase 10: Generate marketing materials

**Success criterion:** Drafts of a blog post, LinkedIn post, and YouTube script are written to `dist/content/` for human review, polishing, and publishing.

This phase automates the "now announce it" step after a pattern ships. Inputs are the `CHANGELOG.md` entry, `marketplace_config.yaml` long description, and upstream release notes. The generator (invoked via `make release-content TEMPLATE_VERSION=<v>`) calls an LLM to produce three artifacts:

| File | Purpose | Length |
|---|---|---|
| `dist/content/blog-post.md` | Draft blog post for fossoncloud.com, with frontmatter | 800-1200 words |
| `dist/content/linkedin-post.md` | LinkedIn post linking to the blog | 150-300 words |
| `dist/content/youtube-script.md` | 3-5 min video script + shot list (cold open, provisioning demo, feature walkthrough, CTA) | ~500 words + annotations |

### 9.1 Run the generator

```bash
AWS_PROFILE=oe-patterns-dev make release-content TEMPLATE_VERSION=<new-version>
```

The generator:
- Reads `CHANGELOG.md` for the current version's release notes
- Reads `marketplace_config.yaml` for product title, long description, architecture
- Fetches upstream release notes (via `gh release view` for GitHub-released projects, or Docker Hub/Meta/release-page scrape for others — per upstream convention)
- Calls an LLM to summarize feature changes and draft each artifact

### 9.2 Review and polish

Treat generated files as drafts. Edit for voice, accuracy, and brand fit. Add screenshots as needed for the blog post. The YouTube script's shot list tells you what to click during the provisioning demo — rehearse it once before recording.

### 9.3 Publish

- **Blog:** commit the polished `.md` to the fossoncloud.com repo.
- **LinkedIn:** post manually from the FOSSonCloud company page.
- **YouTube:** record the video, upload, and link to it from the blog post.

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

### Marketplace submit fails: `IMAGE_ACCESS_EXCEPTION`

**Symptoms:** `make marketplace-status` reports:

```
Error: IMAGE_ACCESS_EXCEPTION
Message: Check if <ami-id> exists in us-east-1 region of 879777583535 AWS account and the AccessARN provided <role-arn> has permissions to share this AMI with AWS Marketplace.
```

Two causes:

1. **Wrong role.** `marketplace_config.yaml` points at `AwsMarketplaceAmiIngestion` (inline policy is incomplete, missing `ec2:DescribeImageAttribute` / `ec2:DescribeSnapshotAttribute`). Switch to `AWSMarketplaceAMIScanning` — its attached managed policy has full Marketplace ingestion perms.
2. **AMI not in the prod account.** You built the AMI under `oe-patterns-dev`. Rebuild under `oe-patterns-prod` (see Phase 3.1).

Both can be fixed without reverting the release branch — edit `marketplace_config.yaml` / rebuild AMI / update `AMI_ID` in the stack, push to `release/<version>`, and re-run `make marketplace-submit` from 6.2. The failed changeset is already in terminal state and does not block a new submission.

### Marketplace submit fails: `delivery_option.<field> is required`

**Symptoms:** `marketplace-submit` exits with:

```
Error: delivery_option.short_description is required in marketplace_config.yaml
```

Or similar for `long_description` or `architecture_diagram_url`.

Fix: add the `delivery_option` block to `marketplace_config.yaml` (see example in Phase 6 Prerequisites). These three fields are mandatory for CloudFormation delivery options on AWS Marketplace.

### `terraform test` fails with certificate not found or RDS snapshot quota

**Symptoms:** Running `terraform test` on a companion `terraform-aws-marketplace-oe-patterns-*` module, the CloudFormation stack rolls back with errors like `Certificate '<arn>' not found` or `Cannot create more than 100 manual snapshots`.

This is **test-environment debt**, not a 2.4.0 regression — the `oe-patterns-test` account accumulates artifacts from every failed test run.

- **Expired ACM cert.** Test domain `test.patterns.ordinaryexperts.com`. Request a new DNS-validated cert in `oe-patterns-test`, add the validation record to Route53 zone `Z04893732CKD1VW1U2A67`, and update `tests/mastodon.tftest.hcl` (or equivalent) with the new ARN.
- **RDS manual snapshot quota at 100.** Delete old test snapshots:
  ```bash
  AWS_PROFILE=oe-patterns-test aws rds describe-db-cluster-snapshots \
    --snapshot-type manual --query "DBClusterSnapshots[?SnapshotCreateTime<'<cutoff-date>'].DBClusterSnapshotIdentifier" \
    --output text | tr '\t' '\n' | xargs -n1 -I{} aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier {}
  ```
- **Stuck `DELETE_FAILED` CloudFormation stacks.** After clearing the snapshot quota, retry `aws cloudformation delete-stack --stack-name <name>` — stacks usually drain cleanly once the DbCluster can create its final snapshot.

**Prevention:** consider a scheduled Lambda in `oe-patterns-test` that (a) deletes manual RDS cluster snapshots older than 30 days, (b) force-deletes `DELETE_FAILED` CloudFormation stacks older than 7 days, (c) alerts on ACM certs expiring in under 30 days.

### Updating product metadata (title, descriptions, highlights)

The AWS Marketplace product's title/short/long description are updated via the Catalog API `UpdateInformation` change type on the `AmiProduct@1.0` entity. Useful when rebranding (e.g., aligning an older "Ordinary Experts X Pattern" product to the "X on AWS by FOSSonCloud" style).

Schema quirks that aren't obvious from AWS docs:

- **Field names are PascalCase**, not camelCase (e.g., `ProductTitle`, not `productTitle`).
- **`Manufacturer` is NOT an `UpdateInformation` field** — it lives on the entity but is only settable at creation. Including it causes `ValidationException`.
- **Other fields live on separate change types**: `UpdateCategories` for categories, `UpdateSearchKeywords` for keywords, `UpdateLogo` for logo, `UpdateSupportInformation` for support description.

Minimum `UpdateInformation` Details for a rebrand (preserves highlights, sku, videoUrls):

```json
{
  "ProductTitle": "X on AWS by FOSSonCloud",
  "ShortDescription": "X on AWS by FOSSonCloud is a custom AMI + ...",
  "LongDescription": "X on AWS by FOSSonCloud is an open-source ...",
  "Sku": "OE_PATTERNS_X",
  "Highlights": ["...", "...", "..."]
}
```

Submit with:

```bash
AWS_PROFILE=oe-patterns-prod aws marketplace-catalog start-change-set \
  --region us-east-1 --catalog AWSMarketplace \
  --change-set-name "rebrand-X-fossoncloud" \
  --change-set '[{"ChangeType":"UpdateInformation","Entity":{"Type":"AmiProduct@1.0","Identifier":"<product-id>"},"Details":"<json-string-of-details>"}]'
```

Metadata changesets typically reach `SUCCEEDED` in under a minute (much faster than `AddDeliveryOptions`/version submissions).

### Reference: existing skills

- `debugging-ec2-user-data` — step-by-step EC2 boot failure investigation
- Pattern repo `CLAUDE.md` — project-specific context and conventions

## Known upstream issues (in this utilities repo)

Track these so pattern upgrades don't get surprised. Several are tied to specific devenv image versions — pin pattern Dockerfiles to `ordinaryexperts/aws-marketplace-patterns-devenv:2.8.3` or newer to pick up all current fixes.

1. **~~`scripts/publish-template.sh` hardcoded the template bucket.~~** *Fixed in devenv `:2.8.3`.* It now honors `template_bucket` and `template_pattern` from `marketplace_config.yaml`, falling back to `ordinary-experts-aws-marketplace-pattern-artifacts` when the file is absent (preserves backward compat for pre-marketplace-API repos).

2. **`scripts/publish-template.sh` uses `--acl public-read`.** The destination bucket must allow public ACLs on uploaded objects — the current dev bucket does, but any future bucket migration needs to preserve this or switch to a bucket-policy-based approach (and remove the `--acl` flag).

3. **~~`scripts/publish-diagram.sh` had the same hardcoded-bucket issue.~~** *Fixed in devenv `:2.8.3`.*

4. **`AwsMarketplaceAmiIngestion` role in `oe-patterns-prod` has an incomplete inline policy.** Use `AWSMarketplaceAMIScanning` instead (has the AWS-managed `AWSMarketplaceAmiIngestion` policy attached). Fix-forward: attach the managed policy to the `AwsMarketplaceAmiIngestion` role and drop its inline `AmiAccess` policy, making both roles interchangeable. The role is not currently managed by Terraform in `aws-infra/terraform/accounts/oe-patterns-prod-879777583535/`, so fixing this cleanly requires importing it into IaC first.

5. **~~`scripts/marketplace.py validate` logo check in wrong place.~~** *Fixed in devenv `:2.8.2`.* Older images check `Description.LogoUrl` instead of `PromotionalResources.LogoUrl` and report a false-positive "missing logo."

6. **`scripts/marketplace.py submit` re-publishes the template internally.** If Phase 6.1.1 already ran under `oe-patterns-dev`, 6.2 re-runs the upload under `oe-patterns-prod`. Whether this succeeds depends on account-specific IAM grants — there is no cross-account bucket policy currently in place. Fix-forward: either skip the internal publish when a `--skip-publish` flag is passed, or change the Phase 6 workflow so template publishing lives only in 6.1.1 and submit references the already-published URL.
