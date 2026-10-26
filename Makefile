SHELL := /bin/bash -eo pipefail
.PHONY: setup format lint build test e2e strip-check run app dmg install

DERIVED_DATA ?= .build/DerivedData
XCODEBUILD := xcodebuild -project Oriel.xcodeproj -scheme Oriel -derivedDataPath $(DERIVED_DATA)
MAC := -destination 'platform=macOS'
comma := ,
BEAUTIFY := $(if $(shell command -v xcbeautify),| xcbeautify $(if $(CI),--renderer github-actions))

setup:
	brew bundle
	git config core.hooksPath .githooks

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

# Runs the UI tests against throwaway herdr sessions, removed even when tests fail.
# ONLY=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB runs just those.
# SHARD=i/n runs every nth test by name from the ith (0-based), for CI's parallel jobs (by name: files hold
# similar tests, so file order split them less evenly). Without the stress tests (ON_DEMAND): a few minutes each, they
# pushed a shard past CI's 20-minute limit; run them with ONLY= (CI: only_testing).
ON_DEMAND := testHundredsOfPanesStayQuick
ifdef SHARD
ONLY := $(shell grep -ho 'func test[A-Za-z0-9_]*' OrielUITests/*.swift | sed 's|func |OrielUITests/OrielUITests/|' \
	| grep -v $(addprefix -e ,$(ON_DEMAND)) | sort | awk -v i=$(word 1,$(subst /, ,$(SHARD))) -v n=$(word 2,$(subst /, ,$(SHARD))) 'NR % n == i' | paste -sd, -)
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
