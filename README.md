# aws-marketplace-utilities

Helpful scripts for managing an AWS Marketplace product

## How to release a new version

1. Set the version environment variable with `export TEMPLATE_VERSION=[version]`
1. Create release branch with `git flow release start $TEMPLATE_VERSION`
1. Update CHANGELOG.md on release branch
1. Build AMI in production account with `ave oe-patterns-prod make TEMPLATE_VERSION=$TEMPLATE_VERSION ami-ec2-build`
1. Set the ami environment variable with `export AMI_ID=[ami from previous step]`
1. Update CDK stack python with updated AMI ID as instructed
1. Synth the template with `make synth-to-file` and test in prod AWS Console
1. Repeat until test passes
1. Download most recent Product Load Form by logging in with `avl oe-patterns-prod-dylan`
1. Visit `https://aws.amazon.com/marketplace/management/homepage?pageType=awsmpmp%3Acustomer#`
1. Publish CFN template to artifacts bucket using `ave oe-patterns-dev make TEMPLATE_VERSION=$TEMPLATE_VERSION publish`
1. Generate PLF row using AMI ID and release version with `ave oe-patterns-prod make AMI_ID=$AMI_ID TEMPLATE_VERSION=$TEMPLATE_VERSION plf`
1. Commit changes to release branch
1. Finish release branch with `git flow release finish [version]`
1. Teardown test stacks with `ave oe-patterns-prod make destroy`
1. Go to develop branch and rebuild ami in dev account, commit to results develop
