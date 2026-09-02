#!/bin/sh
set -e

# Xcode Cloud — préparation du dépôt après le clone.
#
# `MemoBook.xcodeproj` n'est pas versionné : sa source est `ios/project.yml`, et
# XcodeGen le régénère. Sans ce script, Xcode Cloud clone un dépôt sans projet
# Xcode et échoue avant même de compiler.
#
# Xcode Cloud exécute automatiquement le fichier nommé `ci_post_clone.sh` placé
# dans un dossier `ci_scripts`. Il le cherche à côté du projet Xcode — d'où son
# emplacement ici, dans `ios/`. Si Xcode Cloud ne le trouve pas, le déplacer à la
# racine du dépôt : la documentation d'Apple mentionne les deux endroits, et
# c'est le genre de détail qui se vérifie au premier build.

echo "▸ Installation de XcodeGen"
brew install xcodegen

# `CI_PRIMARY_REPOSITORY_PATH` est posé par Xcode Cloud et pointe la racine du
# dépôt cloné. Le repli sert quand on lance le script à la main pour le tester.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"

echo "▸ Génération de MemoBook.xcodeproj"
cd "$REPO_ROOT/ios"
xcodegen generate

echo "✅ Projet généré"
