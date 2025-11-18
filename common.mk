ami-docker-bash: ami-docker-build
	docker compose run --rm ami bash

ami-docker-build:
	docker compose build ami

ami-docker-rebuild:
	docker compose build --no-cache ami

ami-ec2-build:
	@mkdir -p logs
	docker compose run -w /code --rm devenv bash /scripts/packer.sh $(TEMPLATE_VERSION) 2>&1 | tee logs/ami-build-$(shell date +%Y%m%d-%H%M%S).log

ami-ec2-copy:
	docker compose run -w /code --rm devenv bash /scripts/copy-image.sh $(AMI_ID)

bash:
	docker compose run -w /code --rm devenv bash

build:
	docker compose build devenv

cdk-bootstrap:
	docker compose run -w /code/cdk --rm devenv cdk bootstrap aws://992593896645/us-east-1

clean-cdk:
	docker compose run -w /code/cdk --rm devenv rm -rf cdk.out

clean:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh

clean-all-tcat:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh all tcat

clean-all-tcat-all-regions:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh all tcat all

clean-buckets:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh buckets

clean-buckets-tcat:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh buckets tcat

clean-buckets-tcat-all-regions:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh buckets tcat all

clean-logs:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh logs

clean-logs-tcat:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh logs tcat

clean-logs-tcat-all-regions:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh logs tcat all

clean-snapshots:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh snapshots

clean-snapshots-tcat:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh snapshots tcat

clean-snapshots-tcat-all-regions:
	docker compose run -w /code --rm devenv bash /scripts/cleanup.sh snapshots tcat all

destroy: build clean-cdk
	docker compose run -w /code/cdk --rm devenv cdk destroy

diff: clean-cdk
	docker compose run -w /code/cdk --rm devenv cdk diff

gen-plf: build
	docker compose run -w /code --rm devenv python3 /scripts/gen-plf.py $(AMI_ID) $(TEMPLATE_VERSION)

plf: build
	docker compose run -w /code --rm devenv python3 /scripts/plf.py $(AMI_ID) $(TEMPLATE_VERSION)

plf-skip-pricing: build
	docker compose run -w /code --rm devenv python3 /scripts/plf.py $(AMI_ID) $(TEMPLATE_VERSION) --skip-pricing-update

plf-skip-region: build
	docker compose run -w /code --rm devenv python3 /scripts/plf.py $(AMI_ID) $(TEMPLATE_VERSION) --skip-region-update

plf-skip-pricing-and-region: build
	docker compose run -w /code --rm devenv python3 /scripts/plf.py $(AMI_ID) $(TEMPLATE_VERSION) --skip-region-update --skip-pricing-update

lint: build
	docker compose run -w /code --rm devenv bash /scripts/lint.sh

publish: build
	docker compose run -w /code --rm devenv bash /scripts/publish-template.sh $(TEMPLATE_VERSION)

publish-diagram: build
	docker compose run -w /code --rm devenv bash /scripts/publish-diagram.sh $(TEMPLATE_VERSION)

rebuild:
	docker compose build --no-cache devenv

session: build
	@docker compose run -w /code --rm devenv bash -c '\
		REGION=us-east-1; \
		STACK_NAME=oe-patterns-mastodon-$$USER; \
		echo "Getting instance ID from stack: $$STACK_NAME"; \
		ASG_NAME=$$(aws cloudformation describe-stack-resources \
			--region $$REGION \
			--stack-name $$STACK_NAME \
			--logical-resource-id Asg \
			--query "StackResources[0].PhysicalResourceId" \
			--output text); \
		echo "Auto Scaling Group: $$ASG_NAME"; \
		INSTANCE_ID=$$(aws autoscaling describe-auto-scaling-groups \
			--region $$REGION \
			--auto-scaling-group-names $$ASG_NAME \
			--query "AutoScalingGroups[0].Instances[0].InstanceId" \
			--output text); \
		echo "Instance ID: $$INSTANCE_ID"; \
		echo "Starting SSM session..."; \
		aws ssm start-session --region $$REGION --target $$INSTANCE_ID'

synth: build clean-cdk
	docker compose run -w /code/cdk --rm devenv cdk synth \
	--version-reporting false \
	--path-metadata false \
	--asset-metadata false

synth-to-file: build clean-cdk
	mkdir -p dist && docker compose run -w /code --rm devenv bash -c "cd cdk \
	&& cdk synth \
	--version-reporting false \
	--path-metadata false \
	--asset-metadata false > /code/dist/template.yaml \
	&& echo 'Template saved to dist/template.yaml'"

test-all:
	docker compose run -w /code --rm devenv bash -c "cd cdk \
	&& cdk synth > ../test/template.yaml \
	&& cd ../test \
	&& taskcat test run"

test-main:
	docker compose run -w /code --rm devenv bash -c "cd cdk \
	&& cdk synth > ../test/main-test/template.yaml \
	&& cd ../test/main-test \
	&& taskcat test run"

list-all-stacks: build
	docker compose run -w /code --rm devenv bash /scripts/list-all-stacks.sh

# Integration testing targets
# Requires test/integration/ directory with pytest tests
# Projects can override INTEGRATION_TEST_FILE to test different files
INTEGRATION_TEST_FILE ?= test_health.py

test-integration: build
	docker compose run -w /code/test/integration --rm devenv pytest $(INTEGRATION_TEST_FILE) -v

test-integration-ui: build
	docker compose run -w /code/test/integration --rm devenv pytest test_workflows.py -m ui -v

test-integration-all: build
	docker compose run -w /code/test/integration --rm devenv pytest -v
