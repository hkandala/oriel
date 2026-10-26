SHELL := /bin/bash -eo pipefail
.PHONY: setup format lint build test e2e strip-check run app dmg install icons

DERIVED_DATA ?= .build/DerivedData
XCODEBUILD := xcodebuild -project Oriel.xcodeproj -scheme Oriel -derivedDataPath $(DERIVED_DATA)
MAC := -destination 'platform=macOS'
comma := ,
BEAUTIFY := $(if $(shell command -v xcbeautify),| xcbeautify $(if $(CI),--renderer github-actions))

setup:
	brew bundle
	git config core.hooksPath .githooks

# Optional artwork export; Pillow is only needed when regenerating the committed icons.
icons:
	python3 scripts/app-icon.py

format:
	swiftlint lint --fix --quiet
	swiftformat .

lint:
	swiftformat --lint .
	swiftlint lint --strict --quiet

build:
	$(XCODEBUILD) $(MAC) build $(BEAUTIFY)
	$(XCODEBUILD) -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build $(BEAUTIFY)

test:
	swift test --package-path Packages/HerdrKit --scratch-path $(DERIVED_DATA)/HerdrKit
	swiftc -parse-as-library Oriel/Views/ThreeFingers.swift scripts/three-fingers-check.swift -o $(DERIVED_DATA)/three-fingers
	$(DERIVED_DATA)/three-fingers

# Runs the UI tests against throwaway herdr sessions, removed even when tests fail.
# ONLY=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB runs just those.
# SHARD=i/n runs shard i (0-based) of n, split by the tests' measured times (scripts/shard.py, scripts/test-times.tsv);
# SHARD_HEAD=s: shard 0 spends s seconds on other work first. The ON_DEMAND tests are left out: the stress tests, the
# cost and frame-record measurements and the look scenes (minutes in all, numbers and screenshots more than
# behaviour; plan/ci.md). Run them with ON_DEMAND_ONLY=1 (CI: the on_demand input) or ONLY=.
ON_DEMAND := testHundredsOfPanesStayQuick testOverviewOfManyTabsStaysBounded testMemoryAndCPUOverManyTabs \
	testOverviewCostsAndLetsGoAfter testSessionSwipeIntoManyTabsDrawsThemWithTheSidebar \
	testATabComesIntoViewWithoutAFlicker testACardNeverShowsTheOverviewsSmallSnapshot \
	testScenesGlassDark testScenesGlassLight testScenesClassicDark testScenesClassicLight
ifdef SHARD
ONLY := $(shell scripts/shard.py $(SHARD) $(if $(ON_DEMAND_ONLY),--on-demand) --head $(or $(SHARD_HEAD),0) $(ON_DEMAND))
# An empty list would run every test.
$(if $(ONLY),,$(error no tests for SHARD=$(SHARD)))
endif
e2e:
	rm -rf $(DERIVED_DATA)/e2e.xcresult
	scripts/e2e.sh $(XCODEBUILD) $(MAC) \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
		-resultBundlePath $(DERIVED_DATA)/e2e.xcresult $(addprefix -only-testing:,$(subst $(comma), ,$(ONLY))) \
		test $(BEAUTIFY)

# After e2e, which builds the app. It drives the app: the GUI lock (plan/rules.md).
strip-check:
	scripts/strip-check.sh $(DERIVED_DATA)/Build/Products/Debug/Oriel.app

run:
	$(XCODEBUILD) $(MAC) build $(BEAUTIFY)
	open $(DERIVED_DATA)/Build/Products/Debug/Oriel.app $(if $(SESSION),--args -session $(SESSION))

# A Release Oriel.app to copy into /Applications, and a disk image of it. Ad-hoc signed: fine on this Mac;
# another Mac needs right-click > Open once, and notifications need a real signing identity.
app:
	$(XCODEBUILD) $(MAC) -configuration Release build $(BEAUTIFY)
	@echo "$(DERIVED_DATA)/Build/Products/Release/Oriel.app"

install: app
	rm -rf ~/Applications/Oriel.app
	cp -R $(DERIVED_DATA)/Build/Products/Release/Oriel.app ~/Applications/

dmg: app
	rm -f .build/Oriel.dmg
	hdiutil create -volname Oriel -srcfolder $(DERIVED_DATA)/Build/Products/Release/Oriel.app -ov -format UDZO .build/Oriel.dmg

