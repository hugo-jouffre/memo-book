# MemoBook

🇫🇷 **MemoBook** vous permet de capturer et de préserver vos souvenirs, simplement en enregistrant votre voix. Grâce à l'intelligence artificielle, vos récits oraux sont transcrits, enrichis et transformés en un carnet personnalisé, prêt à être partagé et imprimé !

🇬🇧 **MemoBook** lets you capture and preserve your memories, simply by recording your voice. Powered by artificial intelligence, your spoken stories are transcribed, enriched, and transformed into a personalized book, ready to be shared and printed!

Ce repo contient le code de l'**app iOS native MemoBook**, développée en Swift avec l'aide de Claude Code.

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
- **Concurrence** : Swift Concurrency (async/await)
- **Cible** : iOS 17 minimum
- **Backend** : en cours d'arbitrage entre Supabase et Firebase (auth, stockage audio, base de données, fonctions serveur pour appeler les API externes sans exposer les clés)
- **Transcription** : API OpenAI (Whisper / gpt-4o-transcribe), potentiellement hybride avec le framework Speech d'Apple
- **Génération de PDF** : APITemplate
- **Paiements** : StoreKit 2 pour les biens numériques (carnet PDF, abonnement) ; Stripe possible pour les carnets imprimés livrés physiquement
- **CI** : GitHub Actions (vérification de compilation à chaque PR)

Les clés API (OpenAI, APITemplate, etc.) ne vivent **jamais** dans l'app ni dans ce repo — uniquement côté serveur.

## Fonctionnalités (V1)

Développement module par module, chaque module = une branche, une PR, un ticket, une session de QA :

1. **Onboarding** — présentation du concept, demande de permission micro au bon moment
2. **Authentification** — Sign in with Apple + email (magic link), suppression de compte
3. **Enregistrement audio** — cœur de l'app : forme d'onde en temps réel, sauvegarde locale immédiate, reprise après crash
4. **Gestion des souvenirs** — liste, lecture, transcription, édition, synchronisation en arrière-plan
5. **Génération et visualisation du carnet** — composition, génération serveur, prévisualisation PDF
6. **Partage et export** — export PDF, lien de partage, sauvegarde dans Fichiers
7. **Paywall et achats intégrés** — StoreKit 2, achat unique et abonnement
8. **Réglages et compte** — profil, abonnement, confidentialité, suppression de compte

## Roadmap

Développement mené en 8 phases avec Claude Code :

| Phase | Contenu | Statut |
|---|---|---|
| 0 · Prérequis | Environnement, repo GitHub, identifiants | ✅ Fait |
| 1 · Cadrage et design | Specs, user stories, Figma, prototypes | 🔄 En cours |
| 2 · Architecture | SwiftUI/MVVM, backend, transcription, paiements, modèle de données | 🔄 En cours |
| 3 · Setup Xcode | Projet, design system, navigation, secrets, CI | ⏳ À venir |
| 4 · Fonctionnalités | Les 8 modules de la V1 | ⏳ À venir |
| 5 · Backend et intégrations | OpenAI, APITemplate, push, analytics | ⏳ À venir |
| 6 · Tests et TestFlight | Tests auto, QA, beta élargie | ⏳ À venir |
| 7 · App Store | Fiche, conformité, soumission, lancement | ⏳ À venir |

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

La documentation technique détaillée (stack figée, conventions de code Swift, ADR, workflow Git complet) est tenue à jour dans le [Notion MemoBook](https://app.notion.com/p/MemoBook-2a3401e7bdc1805f99c7f6e8be99575e), au fil des phases du projet.
