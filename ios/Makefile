SIMULATOR ?= iPhone 17

.PHONY: project test test-modules test-app build run doctor clean

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

# Compile, installe et lance — **sans se tromper de bundle**.
#
# Xcode garde un dossier DerivedData par emplacement du projet, et le
# `.xcodeproj` se régénère depuis `project.yml` : plusieurs `MemoBook-<hash>`
# finissent par cohabiter. Installer « le » .app à un chemin noté une fois
# revient à lancer une version d'il y a trois jours — l'app se comporte alors
# comme une autre branche, ne fait aucun appel réseau, et résiste aux
# interrupteurs de debug. On a perdu une heure là-dessus le 14 septembre.
#
# `xcodebuild -showBuildSettings` donne le chemin **de ce build-ci**. C'est lui
# qui fait foi, jamais un chemin recopié.
#
# ARGS passe les arguments de lancement :
#   make run ARGS="-previewSignedIn -openOrder"
run: build
	@APP_PATH=$$(xcodebuild -project MemoBook.xcodeproj -scheme MemoBook \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ TARGET_BUILD_DIR = /{d=$$2} / FULL_PRODUCT_NAME = /{n=$$2} END{print d"/"n}'); \
	echo "→ $$APP_PATH"; \
	test -d "$$APP_PATH" || { echo "Bundle introuvable : relance make build."; exit 1; }; \
	xcrun simctl boot '$(SIMULATOR)' 2>/dev/null || true; \
	xcrun simctl install '$(SIMULATOR)' "$$APP_PATH"; \
	xcrun simctl terminate '$(SIMULATOR)' com.memobook.app 2>/dev/null || true; \
	xcrun simctl launch '$(SIMULATOR)' com.memobook.app $(ARGS)

# Le back-end doit tourner pour que l'app ait des données : `make run` ne le
# démarre pas, il le dit.
doctor:
	@echo "Simulateur : $(SIMULATOR)"
	@curl -sf -m 3 http://localhost:3000/health >/dev/null \
		&& echo "Back-end   : debout sur :3000" \
		|| echo "Back-end   : ÉTEINT — lance 'npm run dev' dans backend/, sinon l'app n'aura aucune donnée."

clean:
	rm -rf MemoBook.xcodeproj Modules/.build
