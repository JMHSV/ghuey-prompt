# Override with your stable signing identity to retain Accessibility permission across rebuilds.
SIGN_IDENTITY ?= -
ARCH ?= $(shell uname -m)
APP_NAME := Ghuey Prompt
BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
XCODEBUILD := xcodebuild -destination "platform=macOS,arch=$(ARCH)" -project GhueyPrompt.xcodeproj -scheme GhueyPrompt -derivedDataPath $(BUILD_DIR) -quiet

.PHONY: project build test install icon clean

project:
	xcodegen generate --quiet

build: project
	$(XCODEBUILD) -configuration Release SIGN_IDENTITY="$(SIGN_IDENTITY)" build

test: project
	$(XCODEBUILD) -configuration Debug SIGN_IDENTITY=- test

# Installs to /Applications, registers the Services menu item, and (re)launches.
install: build
	-osascript -e 'quit app "$(APP_NAME)"' 2>/dev/null
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	/System/Library/CoreServices/pbs -update
	open "/Applications/$(APP_NAME).app"

icon:
	swift scripts/make-icon.swift GhueyPrompt/Resources/Assets.xcassets

clean:
	rm -rf $(BUILD_DIR)
