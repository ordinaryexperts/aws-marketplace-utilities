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
