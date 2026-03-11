.PHONY: bootstrap build test coverage ci-check deps-check deploy-local deploy-testnet demo-local demo-testnet demo-launch-window demo-unlock demo-all verify-commits

bootstrap:
	./scripts/bootstrap.sh

deps-check:
	./scripts/bootstrap.sh --check-only

build:
	forge build

test:
	forge test

coverage:
	forge coverage --ir-minimum --exclude-tests --no-match-coverage "script/" --report summary --report lcov

ci-check: deps-check build test coverage

deploy-local:
	./scripts/deploy_local.sh

deploy-testnet:
	./scripts/deploy_testnet.sh

demo-local:
	./scripts/demo_local.sh

demo-testnet:
	./scripts/demo_testnet.sh

demo-launch-window:
	./scripts/demo_launch_window.sh

demo-unlock:
	./scripts/demo_unlock.sh

demo-all:
	./scripts/demo_all.sh

verify-commits:
	./verify_commits.sh
