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
6. **Marketplace publishing** — copy AMI to regions, publish template, update PLF

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
