APP_NAME := GitPulse
PREFIX ?= /Applications
APP := $(PREFIX)/$(APP_NAME).app
BUILT_APP := .build/app/$(APP_NAME).app
CASKROOM = $(shell command -v brew >/dev/null 2>&1 && echo "$$(brew --prefix)/Caskroom/gitpulse")

.PHONY: build test app dev demo install uninstall run clean check-not-cask

build:
	swift build -c release

test:
	swift test

app:
	Scripts/build-app.sh

# Runs the built bundle in place, leaving /Applications (and a Homebrew install) untouched.
dev: app
	open "$(BUILT_APP)"

demo: app
	open "$(BUILT_APP)" --args --demo

check-not-cask:
	@if [ -n "$(CASKROOM)" ] && [ -d "$(CASKROOM)" ]; then \
		echo "error: GitPulse is installed with Homebrew; use 'make dev', or run 'brew uninstall --cask gitpulse' first"; \
		exit 1; \
	fi

install: check-not-cask app
	rm -rf "$(APP)"
	ditto "$(BUILT_APP)" "$(APP)"
	@echo "Installed $(APP). Launch with: open -a $(APP_NAME)"

uninstall: check-not-cask
	rm -rf "$(APP)"

run: install
	open -a "$(APP_NAME)"

clean:
	swift package clean
