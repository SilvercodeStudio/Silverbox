# Shortcuts for building, running and testing eXo Client.
#
#   make run ARGS='-libraryPath /Volumes/eXoDOS_ro -musicEnabled 0'
#
# The app is built with xcodebuild into Xcode's DerivedData, so builds from
# Xcode and from here share the same incremental state.

PROJECT = eXoMAC.xcodeproj
SCHEME = "eXo Client"
CONFIG ?= Debug
ARGS ?=

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS'

.PHONY: help build run app test core typecheck sweep

help:
	@echo "make build          build the app ($(CONFIG)) with xcodebuild"
	@echo "make run            build, then start the app in the foreground; ARGS='...' passes launch arguments"
	@echo "make app            print the path of the built app"
	@echo "make test           run the core tests (swift test)"
	@echo "make core           build the core package only (swift build)"
	@echo "make typecheck      type-check the app sources against the package build, without Xcode"
	@echo "make sweep          translate every eXoDOS config in the mounted library and print a summary"
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

# Walks the real library (/Volumes/eXoDOS_ro or $$EXOMAC_TEST_LIBRARY) and
# reports configs, builds and translation notes without starting anything.
sweep:
	EXOMAC_SWEEP=1 swift test --filter LaunchSweep 2>&1 | grep -v '^\[' 

# Checks that the app only uses public core API, using the package's build
# products instead of Xcode. SwiftUI and AVFoundation come from the SDK.
typecheck: core
	@tmp=$$(mktemp -d); \
	printf 'module CStbVorbis { umbrella "%s/Sources/CStbVorbis/include" export * }\n' "$(CURDIR)" > $$tmp/stb.modulemap; \
	printf 'module CXmpLite { umbrella "%s/Sources/CXmpLite/include" export * }\n' "$(CURDIR)" > $$tmp/xmp.modulemap; \
	swiftc -typecheck -sdk "$$(xcrun --show-sdk-path)" -target arm64-apple-macos27.0 -swift-version 5 \
	    -default-isolation MainActor -enable-upcoming-feature MemberImportVisibility \
	    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
	    -module-name eXoMAC -I .build/out/Products/Debug \
	    -Xcc -fmodule-map-file=$$tmp/stb.modulemap -Xcc -fmodule-map-file=$$tmp/xmp.modulemap \
	    eXoMAC/App/*.swift eXoMAC/Views/*.swift eXoMAC/Services/*.swift eXoMAC/eXoMACApp.swift; \
	status=$$?; rm -rf $$tmp; exit $$status
