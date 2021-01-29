bash: build
	docker-compose run -w /code --rm util bash

build:
	docker-compose build util

clean: build
	docker-compose run -w /code --rm util bash ./scripts/cleanup.sh

gen-plf: build
	docker-compose run -w /code --rm util python3 ./scripts/gen-plf.py $(AMI_ID) $(TEMPLATE_VERSION)

publish: build
	docker-compose run -w /code --rm util bash ./scripts/publish-template.sh $(TEMPLATE_VERSION)

rebuild:
	docker-compose build --no-cache util
