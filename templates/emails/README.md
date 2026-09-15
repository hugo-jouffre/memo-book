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
| `order.coverCaption` | `memos.title` + `pageCount` | « Rome 2026 · 68 pages », **composée par le back-end**. `pageCount` est facultatif en base : le gabarit ne saurait pas quoi faire d'un « · pages » orphelin |
| `order.copies` | `print_orders.copies` | |
| `order.carrier` · `order.trackingUrl` | Renseignés par l'imprimeur | **Sans `trackingUrl`, l'e-mail ne part pas** : un suivi sans lien ne sert à rien |
| `order.shippedOn` | `shippedAt`, formaté | Texte, pas une date : « ce matin » vaut mieux qu'un horodatage |
| `order.estimatedRange` | `estimatedMinDays` / `MaxDays` | « entre le 22 et le 24 septembre ». Deux bornes, jamais un rendez-vous — et une seule chaîne, parce que les deux peuvent manquer |
| `order.shipping.name` · `.line1` · `.cityLine` · `.city` | `shippingName`, `shippingLine1` (+ `line2` replié dedans), `shippingPostalCode` + `shippingCity` | La copie figée de la commande, pas l'adresse du profil. Trois lignes distinctes, et non un bloc d'adresse déjà balisé : une adresse vient de l'utilisateur, elle n'a pas à pouvoir injecter du HTML |
| `order.tracking[]` | Calculé | `{ label, detail, state }`, `state` ∈ `done` \| `current` \| `todo`. La machine à états reste dans le code ; le gabarit ne fait qu'afficher |

> **`recipient.greeting`, et non `recipient.firstName`.** Le prénom est
> facultatif — un compte ouvert par Apple n'en a pas toujours — et le gabarit
> hébergé chez Resend ne sait pas écrire de condition. Le back-end compose donc
> « Clara, » ou la chaîne vide, et le gabarit ne fait que la poser. Même raison
> pour `coverCaption` et `estimatedRange`.

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
npm run emails:preview   # rend avec de vraies valeurs, dans backend/.mail-out/resend/
```

`emails:render` fait la même chose en gardant les marqueurs Resend — utile pour
vérifier ce qui sera poussé, illisible pour juger d'un texte.

---

## Les gabarits chez Resend

Les deux gabarits vivent **aussi** dans le compte Resend, en tant que
*templates* hébergés (`POST /templates`). L'envoi ne transporte alors que des
variables, et la copie devient modifiable sans déploiement — c'est le niveau 2
de [`docs/emails.md`](../../docs/emails.md).

| Alias Resend | Fichier | Objet |
|---|---|---|
| `print-order-shipped` | `print-order-shipped.njk` | Ton carnet « … » est en route |
| `password-reset` | `password-reset.njk` | Réinitialise ton mot de passe MemoBook |

```bash
npm run emails:sync      # crée ou met à jour, puis publie. Exige RESEND_API_KEY
```

L'alias est la clé d'envoi : `POST /emails` accepte `template: { id: "password-reset", variables: { … } }`.
**Un gabarit non publié n'est pas envoyable** — d'où le `publish` que le script
enchaîne systématiquement.

### Ce que la syntaxe Resend change

Un gabarit Resend ne sait faire **qu'une substitution** : `{{{VARIABLE}}}`, en
triple accolade. Ni condition, ni boucle, ni filtre. Trois conséquences, et
elles expliquent la forme des variables ci-dessus :

1. **Tout ce qui peut manquer est composé côté back-end**, en une seule chaîne
   (`greeting`, `coverCaption`, `estimatedRange`).
2. **Un état = un gabarit.** Le suivi de `print-order-shipped` a ses quatre
   étapes figées — deux faites, une en cours, une à venir — parce que c'est ce
   que « expédié » veut dire. La livraison sera `print-order-delivered`, pas une
   condition dans celui-ci.
3. **Le pied de page est figé au moment de la synchronisation.** Les deux
   gabarits sont transactionnels : ni lien de désinscription, ni en-tête
   `List-Unsubscribe`. Une campagne passera par un gabarit à part.

### Qui écrit quoi

Le gabarit Resend est **dérivé**, jamais écrit à la main : `emails:sync` le rend
depuis le `.njk` et l'écrase. Une modification faite dans l'interface Resend
survit donc jusqu'à la prochaine synchronisation, et pas plus.

C'est voulu tant que ces deux e-mails sont de niveau 1 et 2 avec la copie au
dépôt. Le jour où une équipe CRM prend la main sur `print-order-shipped`, c'est
ce fichier-ci qu'il faudra retirer de la liste de `resend-templates.ts` — sans
quoi la première synchronisation effacera son travail.

### Les images

```bash
npm run emails:assets    # publie assets/emails/ et affiche la racine publique
```

Les images vivent sur **`memobook-public`**, un bucket Supabase distinct de
`memobook-media`. Celui-ci est privé et doit le rester : il contient les vocaux
et les photos des voyageurs, qui ne sortent que par une URL signée. Une image
d'e-mail a le besoin exactement inverse — une URL publique, stable, qui ne
périme jamais : une boîte de réception la charge des mois après l'envoi, sans
session, et la moitié d'entre elles la re-téléchargent par un proxy.

La racine se pose dans `MAIL_ASSETS_BASE_URL`, et **elle est figée dans le
gabarit au moment du `emails:sync`**. `emails:sync` refuse donc de pousser si
`<racine>/logo.png` ne répond pas : une en-tête cassée ne se rattrape pas, le
message est déjà parti.

Ni URL S3 signée, qui périme, ni pièce jointe. Et changer le dessin du logo veut
dire **changer le nom du fichier** : il est servi avec un cache d'un an.
