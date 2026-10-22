# Les mêmes cibles que `ios/Makefile`, côté Android.
#
# Gradle demande un JDK 17 ou plus. Sur un Mac où le Java par défaut est plus
# ancien, on prend le JDK 21 de Homebrew (`brew install openjdk@21`) ; le SDK
# Android est celui d'Android Studio, sinon celui de Homebrew
# (`brew install --cask android-commandlinetools`).
BREW := $(shell brew --prefix 2>/dev/null)
export JAVA_HOME ?= $(shell /usr/libexec/java_home -F -v 21 2>/dev/null || echo "$(BREW)/opt/openjdk@21")
export ANDROID_HOME ?= $(firstword $(wildcard $(HOME)/Library/Android/sdk $(BREW)/share/android-commandlinetools))

GRADLE := ./gradlew
ADB := $(ANDROID_HOME)/platform-tools/adb

.PHONY: build test lint release snapshots assets run emulator doctor clean

# Compile l'app en Debug.
build:
	$(GRADLE) :app:assembleDebug

# Tests de tous les modules, sur la JVM : pas d'émulateur.
test:
	$(GRADLE) testDebugUnitTest :core:test

lint:
	$(GRADLE) lintDebug

# Le Release, minifié par R8. La CI le compile à chaque PR : la CI iOS ne
# compile que le Debug, et l'archive a cassé sur du code qu'elle n'avait
# jamais vu.
release:
	$(GRADLE) :app:assembleRelease

# Les captures de référence du design system : chaque @Preview de :design,
# rendue par Robolectric. À relancer après avoir changé un composant, puis
# regarder les images dans design/src/test/screenshots avant de les commiter.
snapshots:
	$(GRADLE) :design:recordRoborazziDebug

# Le catalogue d'images d'iOS recopié dans :design (après un script de
# ios/Tools qui l'a modifié).
assets:
	$(GRADLE) :tools:importBrandAssets

# Installe et lance sur l'émulateur ou le téléphone branché. ARGS passe les
# extras de lancement, comme les arguments du simulateur iOS :
#   make run ARGS="--ez previewSignedIn true"
run:
	$(GRADLE) :app:installDebug
	$(ADB) shell am start -n com.memobook.app/.MainActivity $(ARGS)

# L'émulateur du Mac, dans une fenêtre : le Pixel 8 de `docs/android.md`.
# Le créer la première fois : `sdkmanager "system-images;android-36;google_apis;arm64-v8a"`
# puis `avdmanager create avd -n MemoBook_Pixel -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8`.
emulator:
	$(ANDROID_HOME)/emulator/emulator -avd MemoBook_Pixel -no-audio -no-boot-anim &

# Le back-end doit tourner pour que l'app ait des données : `make run` ne le
# démarre pas, il le dit.
doctor:
	@echo "JAVA_HOME    : $(JAVA_HOME)"
	@echo "ANDROID_HOME : $(ANDROID_HOME)"
	@$(ADB) devices 2>/dev/null | tail -n +2 | grep . || echo "Appareil     : aucun — lance un émulateur ou branche un téléphone."
	@curl -sf -m 3 http://localhost:3000/health >/dev/null \
		&& echo "Back-end     : debout sur :3000 (10.0.2.2:3000 depuis l'émulateur)" \
		|| echo "Back-end     : ÉTEINT — l'émulateur bascule sur la production."

clean:
	$(GRADLE) clean
