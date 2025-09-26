SHELL := /bin/bash

clean:
	rm -rf *.zip source/witch/nodejs/node_modules/

test-cfn:
	cfn_nag templates/*.yaml --blacklist-path ci/cfn_nag_blacklist.yaml

build-static:
	cd source/witch/ && npm install --prefix nodejs mime-types && cp witch.js nodejs/node_modules/

package-static:
	make build-static
	cd source/witch && zip -r ../../witch.zip nodejs

validate:
	./scripts/deploy.sh validate

deploy-dev:
	./scripts/deploy.sh infra dev

deploy-dev-content:
	./scripts/deploy.sh content dev

deploy-staging:
	./scripts/deploy.sh infra staging

deploy-staging-content:
	./scripts/deploy.sh content staging

deploy-prod:
	./scripts/deploy.sh infra prod

deploy-prod-content:
	./scripts/deploy.sh content prod

oidc:
	./scripts/oidc.sh

help:
	./scripts/deploy.sh help

list-envs:
	@jq -r '.environments | keys[]' deploy-config.json

show-config:
	@jq '.' deploy-config.json
