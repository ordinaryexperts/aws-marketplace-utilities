ami-docker-bash: ami-docker-build
	docker-compose run --rm ami bash

ami-docker-build:
	docker-compose build ami

ami-docker-rebuild:
	docker-compose build --no-cache ami

ami-ec2-build:
	docker-compose run -w /code --rm devenv bash /scripts/packer.sh $(TEMPLATE_VERSION)

ami-ec2-copy:
	docker-compose run -w /code --rm devenv bash /scripts/copy-image.sh $(AMI_ID)

bash:
	docker-compose run -w /code --rm devenv bash

build:
	docker-compose build devenv

cdk-bootstrap:
	docker-compose run -w /code/cdk --rm devenv cdk bootstrap aws://992593896645/us-east-1

clean:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh

clean-all-tcat:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh all tcat

clean-all-tcat-all-regions:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh all tcat all

clean-buckets:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh buckets

clean-buckets-tcat:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh buckets tcat

clean-buckets-tcat-all-regions:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh buckets tcat all

clean-logs:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh logs

clean-logs-tcat:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh logs tcat

clean-logs-tcat-all-regions:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh logs tcat all

clean-snapshots:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh snapshots

clean-snapshots-tcat:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh snapshots tcat

clean-snapshots-tcat-all-regions:
	docker-compose run -w /code --rm devenv bash /scripts/cleanup.sh snapshots tcat all

destroy: build
	docker-compose run -w /code/cdk --rm devenv cdk destroy

diff:
	docker-compose run -w /code/cdk --rm devenv cdk diff

gen-plf: build
	docker-compose run -w /code --rm devenv python3 /scripts/gen-plf.py $(AMI_ID) $(TEMPLATE_VERSION)

plf: build
	docker-compose run -w /code --rm devenv python3 /scripts/plf.py $(AMI_ID) $(TEMPLATE_VERSION)

lint: build
	docker-compose run -w /code --rm devenv bash /scripts/lint.sh

publish: build
	docker-compose run -w /code --rm devenv bash /scripts/publish-template.sh $(TEMPLATE_VERSION)

rebuild:
	docker-compose build --no-cache devenv

synth: build
	docker-compose run -w /code/cdk --rm devenv cdk synth \
	--version-reporting false \
	--path-metadata false \
	--asset-metadata false

synth-to-file: build
	docker-compose run -w /code --rm devenv bash -c "cd cdk \
	&& cdk synth \
	--version-reporting false \
	--path-metadata false \
	--asset-metadata false > /code/dist/template.yaml \
	&& echo 'Template saved to dist/template.yaml'"

test-all:
	docker-compose run -w /code --rm devenv bash -c "cd cdk \
	&& cdk synth > ../test/template.yaml \
	&& cd ../test \
	&& taskcat test run"

test-main:
	docker-compose run -w /code --rm devenv bash -c "cd cdk \
	&& cdk synth > ../test/main-test/template.yaml \
	&& cd ../test/main-test \
	&& taskcat test run"

list-all-stacks: build
	docker-compose run -w /code --rm devenv bash /scripts/list-all-stacks.sh
