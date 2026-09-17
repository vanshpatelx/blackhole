APP_NAME   := Black Hole
SCHEME     := BlackHole
PROJECT    := BlackHole.xcodeproj
DERIVED    := build
DEBUG_APP  := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app

.PHONY: project build run demo test dmg clean

## Generate the Xcode project from project.yml (needs `brew install xcodegen`)
project:
	xcodegen generate

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) \
		-destination 'platform=macOS,arch=arm64' build

## Build and launch the app
run: build
	-pkill -x "$(APP_NAME)"
	open "$(DEBUG_APP)"

## Launch with sample data in memory (your real data is untouched)
demo: build
	-pkill -x "$(APP_NAME)"
	open "$(DEBUG_APP)" --args -demoData YES -openWorkspace YES

test: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) \
		-destination 'platform=macOS,arch=arm64' test

## Build a Release DMG into dist/
dmg:
	./scripts/make-dmg.sh

clean:
	rm -rf $(DERIVED) dist $(PROJECT)
