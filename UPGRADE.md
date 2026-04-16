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
