APP_NAME := GHPulse
PREFIX ?= /Applications
APP := $(PREFIX)/$(APP_NAME).app
BINARY := .build/release/$(APP_NAME)
ICONSET := .build/AppIcon.iconset
ICNS := .build/AppIcon.icns

.PHONY: build icon install uninstall run clean

build:
	swift build -c release

icon: $(ICNS)

$(ICNS): Support/genicon.swift
	rm -rf "$(ICONSET)"
	mkdir -p "$(ICONSET)"
	swift Support/genicon.swift "$(ICONSET)"
	iconutil -c icns "$(ICONSET)" -o "$(ICNS)"

install: build $(ICNS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Support/Info.plist "$(APP)/Contents/Info.plist"
	cp "$(BINARY)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp "$(ICNS)" "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)"
	@echo "Installed $(APP). Launch with: open -a $(APP_NAME)"

uninstall:
	rm -rf "$(APP)"

run: install
	open -a "$(APP_NAME)"

clean:
	swift package clean
