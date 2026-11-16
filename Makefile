APP_NAME := GitPulse
PREFIX ?= /Applications
APP := $(PREFIX)/$(APP_NAME).app
BUILT_APP := .build/app/$(APP_NAME).app

.PHONY: build test app install uninstall run demo clean

build:
	swift build -c release

test:
	swift test

app:
	Scripts/build-app.sh

install: app
	rm -rf "$(APP)"
	ditto "$(BUILT_APP)" "$(APP)"
	@echo "Installed $(APP). Launch with: open -a $(APP_NAME)"

uninstall:
	rm -rf "$(APP)"

run: install
	open -a "$(APP_NAME)"

demo:
	open -a "$(APP)" --args --demo

clean:
	swift package clean
