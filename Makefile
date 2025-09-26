SHELL := /bin/bash

clean:
	rm -rf *.zip

test-cfn:
	cfn_nag templates/*.yaml --blacklist-path ci/cfn_nag_blacklist.yaml

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
