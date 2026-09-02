# MemoBook

🇫🇷 **MemoBook** vous permet de capturer et de préserver vos souvenirs, simplement en enregistrant votre voix. Grâce à l'intelligence artificielle, vos récits oraux sont transcrits, enrichis et transformés en un carnet personnalisé, prêt à être partagé et imprimé !

🇬🇧 **MemoBook** lets you capture and preserve your memories, simply by recording your voice. Powered by artificial intelligence, your spoken stories are transcribed, enriched, and transformed into a personalized book, ready to be shared and printed!

Ce repo contient le code de l'**app iOS native MemoBook**, développée en Swift avec l'aide de Claude Code, ainsi que le back-end et le template du carnet.

## Structure du dépôt

| Dossier | Rôle |
|---|---|
| `ios/` | L'app iOS (SwiftUI). [Documentation](ios/README.md) |
| `backend/` | L'API et le pipeline `transcrire → rédiger → relire → mettre en page → imprimer`. [Documentation](backend/README.md) |
| `templates/travel-journal/` | Le template PDF et les schémas qui décrivent le format du carnet. **Source de vérité** : le back-end les lit, il ne les duplique pas |
| `agents/` | Configuration des agents IA et référence du design system. **Source de vérité** : `agent-transcription.md` est chargé tel quel comme prompt système de la rédaction |
| `MemoBook Generator/` | Le générateur de carnets : l'outil de composition à la main, en attendant l'app. Vocaux WhatsApp transcrits, récit découpé en étapes, JSON et PDF générés. [Documentation](MemoBook%20Generator/README.md) |
| `docs/` | Documentation transverse, dont [`ui-development.md`](docs/ui-development.md) : les règles d'implémentation des écrans depuis Figma (unités, fidélité, fiches écran) |

Clara et Paul n'ont rien à installer : tout se lit sur GitHub, et l'app se teste via TestFlight.

## Équipe

| Rôle | Personne | Responsabilité |
|---|---|---|
| Lead produit | Clara | Specs, design, tenue du board de tickets |
| Lead technique | Hugo | Pilote les sessions Claude Code, build et publication TestFlight |
| QA | Paul | Tests et remontée de bugs via TestFlight |
| Développement | Claude | Code, documentation technique, audits |

Le repo GitHub est la source de vérité du projet. Clara et Paul n'ont pas besoin d'Xcode : ils lisent le code sur GitHub et testent l'app via TestFlight sur iPhone. Les builds et l'envoi TestFlight passent par le Mac de Hugo.

## Stack technique

> Décisions d'architecture prises en Phase 2 du projet (voir [Roadmap](#roadmap) ci-dessous) — certaines sont encore en cours de validation.

- **UI** : SwiftUI, architecture **MVVM** avec `@Observable`
- **Concurrence** : Swift Concurrency (async/await), Swift 6 en concurrence stricte
- **Cible** : iOS 17 minimum
- **Xcode** : **26.6**, version de référence partagée par toute l'équipe. En changer se décide ensemble : une autre toolchain modifie les règles de concurrence stricte et casse le build d'une machine à l'autre
- **Projet Xcode** : généré par **XcodeGen** depuis `ios/project.yml`. Le `.xcodeproj` n'est pas versionné — pas de conflit Git sur le pbxproj, et la structure du projet reste lisible en revue de code
- **Backend** : ✅ **tranché — Node/TypeScript (Fastify) + PostgreSQL**, plutôt que Supabase ou Firebase. Le pipeline enchaîne des tâches longues (transcription d'un vocal, appel LLM, génération PDF) qui demandent une vraie file d'attente avec reprise sur échec ; c'est ce qu'un BaaS rend le plus pénible. La file est adossée à Postgres (pg-boss) : rien de plus à opérer
- **Transcription** : API OpenAI (`gpt-4o-transcribe`), langue forcée en français. Hybride avec le framework Speech d'Apple encore possible plus tard
- **Rédaction** : API Anthropic (`claude-opus-5`), pilotée par `agents/agent-transcription.md`. Passe distincte de la mise en page : le texte est écrit souvenir par souvenir et relu par l'utilisateur avant d'entrer dans le carnet
- **Génération de PDF** : APITemplate, sur le template de `templates/travel-journal/`
- **Paiements** : StoreKit 2 pour les biens numériques (carnet PDF, abonnement) ; Stripe possible pour les carnets imprimés livrés physiquement — *pas encore implémenté*
- **CI** : GitHub Actions — typecheck, lint et tests du back-end à chaque PR (`.github/workflows/ci-backend.yml`). La vérification de compilation iOS reste à ajouter (elle demande un runner macOS)

Les clés API (OpenAI, APITemplate, etc.) ne vivent **jamais** dans l'app ni dans ce repo — uniquement côté serveur.

## Fonctionnalités (V1)

Développement module par module, chaque module = une branche, une PR, un ticket, une session de QA :

1. **Onboarding** — présentation du concept, demande de permission micro au bon moment ⏳
2. **Authentification** — Sign in with Apple + email (magic link), suppression de compte ⏳
3. **Enregistrement audio** — cœur de l'app : forme d'onde en temps réel, sauvegarde locale immédiate, reprise après crash — 🔄 *socle posé : capture, forme d'onde, upload. Reste la sauvegarde locale et la reprise après crash*
4. **Gestion des souvenirs** — liste, lecture, transcription, édition, synchronisation en arrière-plan — 🔄 *socle posé : liste, transcription, statuts. Reste l'édition et la synchro en arrière-plan*
5. **Génération et visualisation du carnet** — composition, génération serveur, prévisualisation PDF — 🔄 *socle posé, de bout en bout*
6. **Partage et export** — export PDF, lien de partage, sauvegarde dans Fichiers — 🔄 *partage du PDF en place*
7. **Paywall et achats intégrés** — StoreKit 2, achat unique et abonnement ⏳
8. **Réglages et compte** — profil, abonnement, confidentialité, suppression de compte ⏳

## Roadmap

Développement mené en 8 phases avec Claude Code :

| Phase | Contenu | Statut |
|---|---|---|
| 0 · Prérequis | Environnement, repo GitHub, identifiants | ✅ Fait |
| 1 · Cadrage et design | Specs, user stories, Figma, prototypes | 🔄 En cours |
| 2 · Architecture | SwiftUI/MVVM, backend, transcription, paiements, modèle de données | 🔄 En cours |
| 3 · Setup Xcode | Projet, design system, navigation, secrets, CI | 🔄 En cours |
| 4 · Fonctionnalités | Les 8 modules de la V1 | 🔄 En cours |
| 5 · Backend et intégrations | OpenAI, APITemplate, push, analytics | 🔄 En cours |
| 6 · Tests et TestFlight | Tests auto, QA, beta élargie | ⏳ À venir |
| 7 · App Store | Fiche, conformité, soumission, lancement | ⏳ À venir |

### Où on en est

Le **cœur produit** est posé de bout en bout : on enregistre un vocal, il est transcrit,
structuré en carnet, et le PDF est généré. C'est le chemin critique de l'app — le reste
s'accroche autour.

Ce qui **n'est pas encore là**, volontairement : l'onboarding, l'authentification (l'app
s'enregistre pour l'instant comme un appareil anonyme), le paywall et les réglages. Ces
écrans dépendent d'arbitrages design encore ouverts.

Ce qui **attend une décision** :

- **La palette.** Aucun token de l'app ne porte de couleur de marque pour l'instant — voir
  l'avertissement dans [`ios/README.md`](ios/README.md#design-tokens). Les sources
  existantes se contredisent et vont être remplacées ; rien n'a été figé dans le code.
- **La CI iOS.** Pas encore de vérification de compilation à chaque PR : elle demande un
  runner macOS, à arbitrer (coût en minutes).

## Workflow Git

- Le code vit sur `main`, branche **protégée**
- Une branche `feature/*` par ticket, **PR obligatoire** avant merge
- CI GitHub Actions : vérification de compilation à chaque PR
- Tout travail passe par un ticket (base "Tickets · App iOS MemoBook" dans Notion)

## Sécurité et vie privée

Les données vocales sont des données personnelles (RGPD) :
- Consentement micro explicite, demandé au bon moment (pas pendant l'onboarding)
- Suppression de compte obligatoire (guideline Apple 5.1.1)
- Clés API et secrets jamais commités dans ce repo
- Une revue sécurité/RGPD par un développeur externe est recommandée avant le lancement

## Documentation

- [`docs/ui-development.md`](docs/ui-development.md) — **règles de développement des
  écrans** : unités (tout en rem), fidélité au Figma, rituel écran par écran, fiches et
  checklist. À lire avant de toucher à un écran
- [`agents/design.md`](agents/design.md) — le design system (palette et sémantique)
- [`docs/transcription-whatsapp.md`](docs/transcription-whatsapp.md) — transcrire un
  dossier de vocaux WhatsApp en un fichier texte, depuis le terminal
  (`MemoBook Generator/transcribe-whatsapp.sh`)

La documentation technique détaillée (stack figée, conventions de code Swift, ADR, workflow Git complet) est tenue à jour dans le [Notion MemoBook](https://app.notion.com/p/MemoBook-2a3401e7bdc1805f99c7f6e8be99575e), au fil des phases du projet.
