# Design — Tokens et palette MemoBook

> Référence des couleurs et de leurs usages, source des variables Figma de l'app. À tenir à jour à chaque évolution du design system.

## Scheme (usage sémantique dans l'app)

| Rôle | Couleur associée |
|---|---|
| Text | Brand Colors / Black |
| Accent | Brand Colors / Carrot |
| Foreground | Brand Colors / Beige |
| Background Light | Brand Colors / Beige Cream |
| Background Dark | Brand Colors / Black |

## Brand Colors

| Nom | Hex |
|---|---|
| Carrot | #F86015 |
| Carrot Darker | #B86D18 |
| Forest Green | #19532B |
| Kiwi | #9ABC05 |
| Grey | #C8C8C8 |
| Beige | #FBF3EB |
| Beige Darker | #EFDFCA |
| Beige Cream | #F3E8CC |
| Black | #2B231B |

## Semantic

| Rôle | Hex |
|---|---|
| Error | #DE2B2E |
| Success | #38C13D |
| Warning | #FF682C |
| Information | #5871FB |

## Règles d'usage
- Le texte principal utilise toujours **Black** (#2B231B), jamais un noir pur (#000000)
- **Carrot** (#F86015) est la seule couleur d'accent pour les CTA et éléments interactifs principaux
- **Forest Green** et **Kiwi** sont des couleurs secondaires, réservées aux illustrations et à certains styles de carnet — pas à l'UI de l'app
- Les couleurs sémantiques (Error, Success, Warning, Information) ne servent qu'aux retours système (messages, statuts), jamais en décoration
- Les fonds de carnet suivent le style choisi (`carnet-styles/`), qui peut réutiliser tout ou partie de cette palette

## Utilisé par
- **Agent Mise en page** : applique ces couleurs sur les pages du carnet, dans les limites du style choisi
- **Agent Sélection photo** : évite les retouches qui entreraient en conflit avec la palette de marque

## À faire évoluer
- Typographies de l'app (à documenter dès qu'elles sont figées en Phase 2/3)
- Espacements et grille (à documenter en Phase 3 · Setup Xcode)
