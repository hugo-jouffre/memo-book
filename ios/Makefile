SIMULATOR ?= iPhone 17

.PHONY: project test test-modules test-app build clean

# Régénère MemoBook.xcodeproj depuis project.yml.
# Prérequis : brew install xcodegen
project:
	xcodegen generate

# Tests des modules (MemoBookCore, MemoBookNetworking).
# Le paquet ne cible qu'iOS : xcodebuild pilote directement Package.swift avec
# une destination simulateur — `swift test` compilerait pour macOS et échouerait
# sur AVAudioSession et UIKit.
test: test-modules test-app

test-modules:
	cd Modules && xcodebuild test \
		-scheme MemoBookKit-Package \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)'

# Tests d'assemblage de la cible app. Lance `make project` avant, la première
# fois.
test-app:
	xcodebuild test -project MemoBook.xcodeproj -scheme MemoBook \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)'

# Compile l'app. Lance `make project` avant, la première fois.
build:
	xcodebuild -project MemoBook.xcodeproj -scheme MemoBook \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' build

clean:
	rm -rf MemoBook.xcodeproj Modules/.build
