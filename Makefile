.DEFAULT_GOAL := check
.PHONY: check lint fmt test integration audit clean

SHELLS := harden.sh lib/*.sh tests/*.sh

## check: everything CI runs, except the container job
check: lint test

## lint: shellcheck plus a formatting diff
lint:
	shellcheck -x $(SHELLS)
	shfmt -i 4 -ci -d $(SHELLS)

## fmt: rewrite shell files to canonical formatting
fmt:
	shfmt -i 4 -ci -w $(SHELLS)

## test: unit tests — no root, no container, no sshd required
test:
	bash tests/test_sshd_config.sh

## integration: full run against a real Ubuntu with a real sshd
integration:
	docker build -f tests/Dockerfile -t hardening-test .
	docker run --rm hardening-test

## audit: audit THIS machine, changing nothing
audit:
	./harden.sh audit

clean:
	rm -f ./*.bak-* /tmp/sshd_config.*
