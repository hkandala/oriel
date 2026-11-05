SHELL := /bin/bash -eo pipefail
.PHONY: setup format lint web build build-tests test e2e run app dmg install icons

DERIVED_DATA ?= .build/DerivedData
XCODEBUILD := xcodebuild -project Ovvi.xcodeproj -scheme Ovvi -derivedDataPath $(DERIVED_DATA)
MAC := -destination 'platform=macOS,arch=$(shell uname -m)'
comma := ,
# Swift's warnings-as-errors leaves some concurrency warnings as warnings: any warning in our own sources fails. Matched
# by the path in the repo, since the compiler prints a symlinked path (/tmp) where CURDIR is the real one; the warned
# files are touched so the next build compiles them again and fails again (Xcode does not replay warnings).
NOWARN := | awk '{ print } /(^|\/)(Ovvi|OvviUITests|Packages)\/[^:]*:[0-9]+:[0-9]+: warning: / { w = 1; \
	split($$0, at, ":"); warned[at[1]] } END { for (f in warned) system("touch -c \"" f "\""); exit w }'
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

# What the app carries for its plugins (.build/web, copied into its resources): the plugin API's runtime (ovvi.js,
# checked against its types) and card.css, which every plugin's page loads; the host types package (plugin-api), which
# the app writes into the plugins folder for tsc; the default plugins' source (defaults/<id>, no node_modules or
# dist), which the app installs into the plugins folder on first launch and builds there with their own build scripts;
# and the template a new plugin starts from (template). Each one is installed, type-checked (against
# plugins/node_modules/@ovvi/plugin-api, a link to web/ovvi) and built here too, as a user's would be.
PLUGINS := explorer git template
web: web/node_modules/.package-lock.json $(PLUGINS:%=plugins/%/node_modules/.package-lock.json)
	rm -rf .build/web
	mkdir -p plugins/node_modules/@ovvi && ln -sfn ../../../web/ovvi plugins/node_modules/@ovvi/plugin-api
	for id in $(PLUGINS); do npm --prefix plugins/$$id run --silent check && npm --prefix plugins/$$id run --silent build \
		|| exit 1; done
	mkdir -p .build/web/defaults .build/web/plugin-api
	rsync -a --exclude node_modules --exclude dist plugins/explorer plugins/git .build/web/defaults/
	rsync -a --exclude node_modules --exclude dist plugins/template .build/web/
	web/node_modules/.bin/tsc -p web/ovvi
	web/node_modules/.bin/esbuild web/ovvi/runtime.ts --bundle --format=esm --minify --target=safari18 \
		--log-level=warning --outfile=.build/web/ovvi.js
	cp web/ovvi/card.css .build/web/
	cp web/ovvi/ovvi.d.ts web/ovvi/package.json .build/web/plugin-api/

plugins/%/node_modules/.package-lock.json: plugins/%/package-lock.json
	npm ci --prefix plugins/$* --no-audit --no-fund

web/node_modules/.package-lock.json: web/package-lock.json
	npm ci --prefix web --no-audit --no-fund

build: web
	$(XCODEBUILD) $(MAC) build $(NOWARN) $(BEAUTIFY)

# The app and the UI tests, built but not run (CI's push checks).
build-tests: web
	$(XCODEBUILD) $(MAC) build-for-testing $(NOWARN) $(BEAUTIFY)

test:
	swift test --package-path Packages/HerdrKit --scratch-path $(DERIVED_DATA)/HerdrKit
	@# The About window's Acknowledgements hold every icon license as build.mjs writes it.
	python3 -c 'import pathlib, sys; texts = pathlib.Path("Ovvi/Acknowledgements.txt").read_text(); \
		sys.exit([f"{f} is not in Ovvi/Acknowledgements.txt" for f in pathlib.Path("resources/icons/licenses").iterdir() \
			if f.read_text().strip() not in texts] or None)'
	@# cli.mdx shows the script Ovvi carries.
	python3 -c 'import pathlib, sys; sys.exit("```sh\n" + pathlib.Path("Ovvi/Agent/ovvi.sh").read_text() + "```" not in \
		pathlib.Path("docs/content/docs/agent-control/cli.mdx").read_text() and "cli.mdx: The script differs from Ovvi/Agent/ovvi.sh")'

# Runs the UI tests against throwaway herdr sessions, removed even when tests fail.
# ONLY=OvviUITests/OvviUITests/testA,OvviUITests/OvviUITests/testB runs just those.
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
		$(if $(ONLY),$(addprefix -only-testing:,$(subst $(comma), ,$(ONLY))),$(addprefix -skip-testing:OvviUITests/OvviUITests/,$(ON_DEMAND))) \
		test $(BEAUTIFY)

run: web
	$(XCODEBUILD) $(MAC) build $(NOWARN) $(BEAUTIFY)
	open $(DERIVED_DATA)/Build/Products/Debug/Ovvi.app $(if $(SESSION),--args -session $(SESSION))

# A Release Ovvi.app to copy into ~/Applications, and a disk image of it. Ad-hoc signed: fine on this Mac;
# another Mac needs right-click > Open once, and notifications need a real signing identity.
app: web
	$(XCODEBUILD) $(MAC) -configuration Release build $(NOWARN) $(BEAUTIFY)
	@echo "$(DERIVED_DATA)/Build/Products/Release/Ovvi.app"

# Also links the ovvi skill for pi and Codex (~/.agents/skills) and Claude Code (~/.claude/skills), where no ovvi
# skill is; -f replaces a link whose checkout is gone.
install: app
	rm -rf ~/Applications/Ovvi.app
	cp -R $(DERIVED_DATA)/Build/Products/Release/Ovvi.app ~/Applications/
	for d in ~/.agents/skills ~/.claude/skills; do mkdir -p $$d; [ -e $$d/ovvi ] || ln -sfn $(CURDIR)/skills/ovvi $$d/ovvi; done

dmg: app
	rm -f .build/Ovvi.dmg
	hdiutil create -volname Ovvi -srcfolder $(DERIVED_DATA)/Build/Products/Release/Ovvi.app -ov -format UDZO .build/Ovvi.dmg

