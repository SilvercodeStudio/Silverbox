# Shortcuts for building, running and testing Silverbox.
#
#   make run ARGS='-libraryPath /Volumes/eXoDOS_ro -musicEnabled 0'
#
# The app is built with xcodebuild into Xcode's DerivedData, so builds from
# Xcode and from here share the same incremental state.

PROJECT = Silverbox.xcodeproj
SCHEME = "Silverbox"
CONFIG ?= Debug
ARGS ?=

# Debug builds only this Mac's architecture (named, as the project also
# builds for Intel and xcodebuild would otherwise pick one of the two). A
# Release build goes to a generic Mac, so it holds every architecture in
# ARCHS (Apple silicon and Intel).
ARCH := $(shell uname -m)
comma := ,
DESTINATION = $(if $(filter Release,$(CONFIG)),generic/platform=macOS,platform=macOS$(comma)arch=$(ARCH))
XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DESTINATION)'

# The Swift sources that swift-format checks; the vendored C targets are untouched.
SWIFT_SOURCES = Package.swift Sources/SilverboxCore Silverbox Tests
# Where make install-app puts the app. A leading ~ becomes the home folder: zsh leaves it
# alone in APP_DIR=~/..., and make would make a folder named ~ in the repository.
APP_DIR ?= $(HOME)/Applications
override APP_DIR := $(patsubst ~%,$(HOME)%,$(APP_DIR))
# Registers a copied app with Launch Services, so that the Dock and Finder show its new icon.
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: help build run app test core typecheck sweep format lint install-app open-app dist reset site site-shots

# Never as root: a build with sudo leaves files in .build and DerivedData that only root can
# replace, and every build after it fails.
ifeq ($(shell id -u),0)
$(error Do not run make as root (sudo): it leaves build files that only root can replace. Run it as yourself)
endif

help:
	@echo "make build          build the app ($(CONFIG)) with xcodebuild"
	@echo "make run            build, then start the app in the foreground; ARGS='...' passes launch arguments"
	@echo "make app            print the path of the built app"
	@echo "make test           run the core tests (swift test)"
	@echo "make core           build the core package only (swift build)"
	@echo "make typecheck      type-check the app sources against the package build, without Xcode"
	@echo "make sweep          translate every eXoDOS config in the mounted library and print a summary"
	@echo "make format         reformat the Swift sources with swift-format (settings in .swift-format)"
	@echo "make lint           report formatting problems, trailing whitespace, and a version that is not set right, without changing files"
	@echo "make install-app    build the app for release (Apple silicon and Intel) and copy it to APP_DIR ($(APP_DIR))"
	@echo "make open-app       make install-app, then open the app"
	@echo "make dist           the app for others: Developer ID, notarized, stapled, in a disk image in build/dist (NOTARIZE=0 stops before Apple)"
	@echo "make reset          delete the app's settings and data, to test a first start (asks first; DATA= for a moved data folder)"
	@echo "make site           serve the website (docs/site) at http://localhost:$(SITE_PORT)"
	@echo "make site-shots     take the site's screenshots again, scene by scene (SCENES='library welcome', APPEARANCES=dark for some)"
	@echo "Set CONFIG=Release for a release build (Apple silicon and Intel)."

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

# Walks the real library (/Volumes/eXoDOS_ro or $$SILVERBOX_TEST_LIBRARY) and
# reports configs, builds and translation notes without starting anything.
sweep:
	SILVERBOX_SWEEP=1 swift test --filter LaunchSweep 2>&1 | grep -v '^\['

# Reformats the Swift sources; .swift-format at the repo root holds the
# settings (4-space indent, 120 columns).
format:
	xcrun swift-format format --in-place --recursive $(SWIFT_SOURCES)

# Text files with spaces or tabs at the ends of lines; .editorconfig has editors trim them. License
# texts, vendored code, and drawings stay as their authors and tools wrote them.
WHITESPACE_EXCEPTIONS = ':!LICENSE' ':!NOTICE' ':!*.svg' ':!Silverbox/Licenses' ':!Sources/CStbVorbis' ':!Sources/CXmpLite'

lint:
	xcrun swift-format lint --strict --recursive $(SWIFT_SOURCES)
	@if git grep -nI -E '[[:blank:]]+$$' -- . $(WHITESPACE_EXCEPTIONS); then \
		echo "Spaces or tabs at the end of the lines above: remove them."; exit 1; fi
	@scripts/version.sh check

# A universal release build of the app, copied whole; an older copy is replaced.
# The path check guards the rm -rf: when xcodebuild prints no settings (or under
# make -n, which still runs the lines with $(MAKE)), the path would be wrong.
install-app:
	@$(MAKE) build CONFIG=Release
	@app="$$($(MAKE) app CONFIG=Release)"; \
	case "$$app" in /*.app) [ -d "$$app" ] ;; *) false ;; esac || \
		{ echo "No built app found (got '$$app'); nothing replaced."; exit 1; }; \
	install -d "$(APP_DIR)"; \
	rm -rf "$(APP_DIR)/$$(basename "$$app")"; \
	ditto "$$app" "$(APP_DIR)/$$(basename "$$app")"; \
	touch "$(APP_DIR)/$$(basename "$$app")"; \
	$(LSREGISTER) -f "$(APP_DIR)/$$(basename "$$app")"; \
	echo "Installed $(APP_DIR)/$$(basename "$$app")"

# install-app, then open the app. A copy that is running must quit first,
# because install-app replaces it.
open-app:
	@if pgrep -f "$(APP_DIR)/Silverbox.app/Contents/MacOS/Silverbox" >/dev/null; then \
		echo "Quit Silverbox first: install-app replaces it."; exit 1; fi
	@$(MAKE) install-app && open "$(APP_DIR)/Silverbox.app"

# The app as others get it: archived, exported with Developer ID, notarized, stapled, and put in a
# signed, notarized disk image in build/dist, and added to the update feed
# (docs/site/appcast.xml). See scripts/dist.sh for NOTARY_PROFILE, NOTARIZE=0, FEED=0, and
# ALLOW_DIRTY=1, and docs/internal/Releasing.md.
dist:
	@scripts/dist.sh

# Checks that the app only uses public core API, using the package's build
# products instead of Xcode. SwiftUI and AVFoundation come from the SDK.
typecheck: core
	@tmp=$$(mktemp -d); \
	printf 'module CStbVorbis { umbrella "%s/Sources/CStbVorbis/include" export * }\n' "$(CURDIR)" > $$tmp/stb.modulemap; \
	printf 'module CXmpLite { umbrella "%s/Sources/CXmpLite/include" export * }\n' "$(CURDIR)" > $$tmp/xmp.modulemap; \
	swiftc -typecheck -sdk "$$(xcrun --show-sdk-path)" -target arm64-apple-macos15.0 -swift-version 5 \
	    -default-isolation MainActor -enable-upcoming-feature MemberImportVisibility \
	    -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
	    -module-name Silverbox -I .build/out/Products/Debug \
	    -Xcc -fmodule-map-file=$$tmp/stb.modulemap -Xcc -fmodule-map-file=$$tmp/xmp.modulemap \
	    Silverbox/App/*.swift Silverbox/Views/*.swift Silverbox/Services/*.swift Silverbox/SilverboxApp.swift; \
	status=$$?; rm -rf $$tmp; exit $$status

# Deletes everything the app has written, so the next start is a first start:
# the Application Support folder (user-library.json, and the local data
# folder when it is the default: installed games, save backups, overrides,
# overlays, soundtracks, launch configs, logs, caches) and the settings (the
# app's defaults domain, which also holds the window positions). The libraries
# themselves are never touched. Set DATA= to the local data folder when
# Settings points it at another drive; YES=1 skips the question.
APPDATA = $(HOME)/Library/Application Support/Silverbox
DATA ?=
DOMAIN ?= app.getsilverbox.Silverbox

reset:
	@if pgrep -xq "Silverbox"; then echo "Quit Silverbox first."; exit 1; fi
	@echo "This deletes:"; \
	size=$$([ -e "$(APPDATA)" ] && du -sh "$(APPDATA)" | cut -f1 || echo missing); echo "  app data     $(APPDATA) ($$size)"; \
	if [ -n "$(DATA)" ]; then size=$$([ -e "$(DATA)" ] && du -sh "$(DATA)" | cut -f1 || echo missing); echo "  data folder  $(DATA) ($$size)"; fi; \
	echo "  settings     $(DOMAIN)"; \
	if [ "$(YES)" != 1 ]; then printf "Continue? [y/N] "; read answer; [ "$$answer" = y ] || [ "$$answer" = Y ] || { echo "Nothing deleted."; exit 1; }; fi
	@rm -rf "$(APPDATA)"
	@[ -z "$(DATA)" ] || rm -rf "$(DATA)"
	@defaults delete $(DOMAIN) >/dev/null 2>&1 || true
	@echo "Done. The next start asks for a library again; make run ARGS='-libraryPath /Volumes/eXoDOS_ro' skips that for one run."

# The website, as GitHub Pages serves it. Port 8001, so Silverside's site can run on 8000 beside it.
SITE_PORT ?= 8001
site:
	python3 -m http.server $(SITE_PORT) --bind 127.0.0.1 --directory docs/site

# The site's screenshots, one scene at a time (docs/site/tools/screenshots.sh).
site-shots: build
	@app="$$($(XCODEBUILD) -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR =/ {dir=$$2} /^ *FULL_PRODUCT_NAME =/ {name=$$2} END {print dir "/" name}')"; \
	APP="$$app" SCENES="$(SCENES)" APPEARANCES="$(APPEARANCES)" docs/site/tools/screenshots.sh
