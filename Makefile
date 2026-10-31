SHELL := /bin/bash -eo pipefail
.PHONY: setup format lint web build build-tests test e2e strip-check run app dmg install icons

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

# The default plugins' pages (Oriel/Plugins/Web), a folder per plugin that the scheme serves as
# oriel-plugin://<id>/: its pages (one module each, shared chunks) and its package.json, which the registry reads.
# File Explorer is a package (plugins/explorer) built from its entry with its own node_modules, its types checked
# against the plugin API's (plugins/node_modules/@oriel/plugin-api, a link to web/oriel). Beside them the plugin API's
# runtime (oriel.js, checked against its types) and card.css, which every plugin's page loads. The project copies
# .build/web into the app's resources.
ESBUILD = web/node_modules/.bin/esbuild --bundle --splitting --format=esm --minify --target=safari18 \
	--log-level=warning --external:*.svg --external:*.gif

web: web/node_modules/.package-lock.json plugins/explorer/node_modules/.package-lock.json
	rm -rf .build/web
	mkdir -p plugins/node_modules/@oriel && ln -sfn ../../../web/oriel plugins/node_modules/@oriel/plugin-api
	web/node_modules/.bin/tsc -p plugins/explorer
	$(ESBUILD) plugins/explorer/main.ts --outdir=.build/web/explorer
	$(ESBUILD) web/src/{git,diff}.ts web/src/{git,diff}.css --outdir=.build/web/git
	for id in explorer git; do cp plugins/$$id/package.json .build/web/$$id/; done
	web/node_modules/.bin/tsc -p web/oriel
	web/node_modules/.bin/esbuild web/oriel/runtime.ts --bundle --format=esm --minify --target=safari18 \
		--log-level=warning --outfile=.build/web/oriel.js
	cp web/oriel/card.css .build/web/
	@# pdf.js's worker, decoders, fonts and character maps, which it loads by name from the page's folder. Its viewer's
	@# CSS names images of the editing tools the cards leave out.
	cd plugins/explorer/node_modules/pdfjs-dist && cp build/pdf.worker.min.mjs wasm/{openjpeg,jbig2,qcms_bg}.wasm \
		standard_fonts/*.{pfb,ttf} cmaps/*.bcmap ../../../../.build/web/explorer

plugins/explorer/node_modules/.package-lock.json: plugins/explorer/package-lock.json
	npm ci --prefix plugins/explorer --no-audit --no-fund

web/node_modules/.package-lock.json: web/package-lock.json
	npm ci --prefix web --no-audit --no-fund

build: web
	$(XCODEBUILD) $(MAC) build $(BEAUTIFY)

# The app and the UI tests, built but not run (CI's push checks).
build-tests: web
	$(XCODEBUILD) $(MAC) build-for-testing $(BEAUTIFY)

test:
	swift test --package-path Packages/HerdrKit --scratch-path $(DERIVED_DATA)/HerdrKit
	@# The About window's Acknowledgements hold every icon license as build.mjs writes it.
	python3 -c 'import pathlib, sys; texts = pathlib.Path("Oriel/Acknowledgements.txt").read_text(); \
		sys.exit([f"{f} is not in Oriel/Acknowledgements.txt" for f in pathlib.Path("resources/icons/licenses").iterdir() \
			if f.read_text().strip() not in texts] or None)'

# Runs the UI tests against throwaway herdr sessions, removed even when tests fail.
# ONLY=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB runs just those.
# SHARD=i/n runs shard i (0-based) of n, split by the tests' measured times (scripts/shard.py, scripts/test-times.tsv).
# Without ONLY, the ON_DEMAND tests are left out: the stress tests, the cost and frame-record measurements and the
# look scenes (minutes in all, numbers and screenshots more than behaviour; playbook/ci.md). ON_DEMAND_ONLY=1 runs only them (CI: the on_demand input).
ON_DEMAND := testHundredsOfPanesStayQuick testOverviewOfManyTabsStaysBounded testMemoryAndCPUOverManyTabs \
	testOverviewCostsAndLetsGoAfter testSessionSwipeIntoManyTabsDrawsThemWithTheSidebar \
	testATabComesIntoViewWithoutAFlicker testACardNeverShowsTheOverviewsSmallSnapshot \
	testScenesGlassDark testScenesGlassLight testScenesClassicDark testScenesClassicLight \
	testKeptCardsCost testManyKeptCardsCost
ifdef ON_DEMAND_ONLY
SHARD ?= 0/1
endif
ifdef SHARD
ONLY := $(shell scripts/shard.py $(SHARD) $(if $(ON_DEMAND_ONLY),--on-demand) $(ON_DEMAND))
# An empty list would run every test.
$(if $(ONLY),,$(error no tests for SHARD=$(SHARD)))
endif
e2e: web
	rm -rf $(DERIVED_DATA)/e2e.xcresult
	scripts/e2e.sh $(XCODEBUILD) $(MAC) \
		-test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
		-resultBundlePath $(DERIVED_DATA)/e2e.xcresult \
		$(if $(ONLY),$(addprefix -only-testing:,$(subst $(comma), ,$(ONLY))),$(addprefix -skip-testing:OrielUITests/OrielUITests/,$(ON_DEMAND))) \
		test $(BEAUTIFY)

# After e2e, which builds the app. It drives the app: the GUI lock (playbook/workflow.md).
strip-check:
	scripts/strip-check.sh $(DERIVED_DATA)/Build/Products/Debug/Oriel.app

run: web
	$(XCODEBUILD) $(MAC) build $(BEAUTIFY)
	open $(DERIVED_DATA)/Build/Products/Debug/Oriel.app $(if $(SESSION),--args -session $(SESSION))

# A Release Oriel.app to copy into ~/Applications, and a disk image of it. Ad-hoc signed: fine on this Mac;
# another Mac needs right-click > Open once, and notifications need a real signing identity.
app: web
	$(XCODEBUILD) $(MAC) -configuration Release build $(BEAUTIFY)
	@echo "$(DERIVED_DATA)/Build/Products/Release/Oriel.app"

install: app
	rm -rf ~/Applications/Oriel.app
	cp -R $(DERIVED_DATA)/Build/Products/Release/Oriel.app ~/Applications/

dmg: app
	rm -f .build/Oriel.dmg
	hdiutil create -volname Oriel -srcfolder $(DERIVED_DATA)/Build/Products/Release/Oriel.app -ov -format UDZO .build/Oriel.dmg

