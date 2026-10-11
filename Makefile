# Shortcuts for building, running and testing eXo Client.
#
#   make run ARGS='-libraryPath /Volumes/eXoDOS_ro -musicEnabled 0'
#
# The app is built with xcodebuild into Xcode's DerivedData, so builds from
# Xcode and from here share the same incremental state.

PROJECT = eXoMAC.xcodeproj
SCHEME = eXoMAC
CONFIG ?= Debug
ARGS ?=

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS'

.PHONY: help build run app test core

help:
	@echo "make build          build the app ($(CONFIG)) with xcodebuild"
	@echo "make run            build, then start the app in the foreground; ARGS='...' passes launch arguments"
	@echo "make app            print the path of the built app"
	@echo "make test           run the core tests (swift test)"
	@echo "make core           build the core package only (swift build)"
	@echo "Set CONFIG=Release for a release build."

build:
	$(XCODEBUILD) -quiet build

run: build
	@app="$$($(XCODEBUILD) -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR =/ {dir=$$2} /^ *EXECUTABLE_PATH =/ {exe=$$2} END {print dir "/" exe}')"; \
	echo "Starting $$app $(ARGS)"; \
	"$$app" $(ARGS)

app:
	@$(XCODEBUILD) -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR =/ {dir=$$2} /^ *FULL_PRODUCT_NAME =/ {name=$$2} END {print dir "/" name}'

test:
	swift test

core:
	swift build
