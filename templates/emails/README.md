# Gabarits d'e-mail

> L'architecture — qui déclenche quoi, qui a le droit de modifier quoi — est
> dans [`docs/emails.md`](../../docs/emails.md). Ce fichier-ci est le **contrat**
> entre le back-end qui fournit les données et le gabarit qui les affiche.

## Organisation

| Fichier | Rôle |
|---|---|
| `layout.njk` | En-tête, pied de page, palette, parades de compatibilité. **Modifié une fois, il change tous les e-mails.** |
| `<clé>.njk` | Un e-mail. N'écrit que son contenu, hérite du reste |

La clé du fichier est la clé de l'e-mail : `print-order-shipped.njk` porte
`print_order.shipped`, et c'est cette clé que `outbound_messages.templateKey`
enregistre et que le CRM reprendra à l'identique.

## Variables communes à tous les e-mails

Fournies par l'expéditeur, jamais par l'appelant — un gabarit n'a pas à savoir
d'où vient l'adresse du pied de page.

| Variable | Exemple | Note |
|---|---|---|
| `brand.assetsBaseUrl` | `https://cdn.memo-book.com/emails` | **Sans barre oblique finale.** Les images d'e-mail doivent être servies par une URL publique et stable : ni S3 signé (il périme), ni pièce jointe |
| `brand.address` | `12 rue des Voyages, 75011 Paris` | Adresse postale, obligatoire sur les campagnes |
| `brand.supportEmail` | `bonjour@memo-book.com` | Une boîte réellement lue |
| `message.class` | `transactional` \| `marketing` | **Seul discriminant du pied de page.** Une campagne sans lien de désinscription est une infraction |
| `message.reason` | `tu as commandé un carnet imprimé` | Complète « Tu reçois cet e-mail parce que… ». Transactionnel uniquement |
| `message.preheader` | — | La ligne d'aperçu de la boîte de réception. Chaque gabarit la redéfinit |
| `links.web` | `https://memo-book.com` | Cible du logo |
| `links.preferences` | `…/preferences?t=<jeton>` | Jeton signé : le lien s'ouvre sans se connecter |
| `links.unsubscribe` | `…/desabonnement?t=<jeton>` | Marketing uniquement. Doublé par l'en-tête `List-Unsubscribe` |
| `recipient.firstName` | `Clara` | Peut être vide — écrire des phrases qui tiennent sans |

## Variables de `print_order.shipped`

Le gabarit d'exemple. Tout vient de `print_orders`, déjà en base.

| Variable | Source | Note |
|---|---|---|
| `order.reference` | `id`, raccourci | Ce que le support demandera |
| `order.memoTitle` | `memos.title` | |
| `order.coverImageUrl` | `print_orders.coverImageUrl` | Figée avec le rendu : c'est le carnet commandé, pas celui d'aujourd'hui |
| `order.pageCount` | `print_orders.pageCount` | |
| `order.copies` | `print_orders.copies` | |
| `order.carrier` · `order.trackingUrl` | Renseignés par l'imprimeur | **Sans `trackingUrl`, l'e-mail ne part pas** : un suivi sans lien ne sert à rien |
| `order.shippedOn` | `shippedAt`, formaté | Texte, pas une date : « ce matin » vaut mieux qu'un horodatage |
| `order.estimatedFrom` · `order.estimatedTo` | `estimatedMinDays` / `MaxDays` | Deux bornes, jamais un rendez-vous |
| `order.shipping.*` | `shippingName`, `shippingLine1`, `shippingPostalCode`, `shippingCity` | La copie figée de la commande, pas l'adresse du profil |
| `order.tracking[]` | Calculé | `{ label, detail, state }`, `state` ∈ `done` \| `current` \| `todo`. La machine à états reste dans le code ; le gabarit ne fait qu'afficher |

## Ce qu'un client d'e-mail sait faire, et ne sait pas faire

Outlook rend le HTML avec le moteur de Word. Cinq règles suffisent à ne jamais
s'y casser les dents :

1. **Des tables, et rien d'autre.** Pas de `flex`, pas de `grid`, pas de
   `position`, pas de `float`.
2. **Le style en ligne pour tout ce qui compte.** La balise `<style>` ne sert
   qu'aux media queries et aux réinitialisations : Gmail la garde en ligne, la
   plupart des autres aussi, mais aucun client n'est obligé de la lire.
3. **Pas de SVG.** Gmail le supprime sans le remplacer. Le logo est un PNG, à
   deux ou trois fois sa taille d'affichage.
4. **Pas d'image indispensable.** Une boîte sur deux les bloque par défaut :
   tout ce qui doit être lu est du texte, et chaque image porte un `alt`.
5. **600 px, et une seule colonne en dessous de 620 px.** Les media queries
   qu'Outlook ignore le laissent sur 600 px fixes — ce qui est exactement le
   comportement voulu.

Ce que le gabarit assume malgré tout : les `border-radius` (carrés chez Outlook,
c'est acceptable) et le chargement de **Sora** pour les titres. Apple Mail et
Mail iOS la chargent, c'est-à-dire la quasi-totalité de nos lecteurs ; les
autres retombent sur la pile système. Le corps de texte n'essaie même pas —
General Sans n'est pas distribuée par Google Fonts, et un e-mail n'est pas
l'endroit où parier sur un chargement de police.

Le mode sombre est **refusé explicitement** (`color-scheme: light`). Gmail et
Outlook inversent sinon les couleurs qu'on ne revendique pas, et le crème de la
marque y vire au gris sale.

## Rendre un gabarit pour le relire

```bash
node scripts/render-email.mjs print-order-shipped
```

*(Script à écrire — voir l'étape 4 de `docs/emails.md`. Il rend le gabarit avec
un jeu de données d'exemple et ouvre le résultat, sur le modèle de
`backend/scripts/render-local.ts`.)*
