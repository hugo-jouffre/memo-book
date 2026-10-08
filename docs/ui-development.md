# Interface iOS — ce qui reste à régler

Ce fichier ne garde que ce qui **attend encore une réponse** : les tickets
ouverts, écran par écran. Il faisait 4 165 lignes ; tout ce qui était réglé — fiches écran, lots, réponses aux
tickets, contrats back-end — est dans
[`docs/archive/ui-development-journal.md`](archive/ui-development-journal.md),
intact. C'est là que renvoient les « § » cités dans le code et les autres docs.

**Pour répondre** : un mot en face du numéro suffit (« validé », « à
refaire », « v2 »…). **Un ticket réglé quitte sa table** — il ne reste pas
coché ; ce qui a été fait se raconte dans la PR qui le règle. Chaque ligne a
trois colonnes : `| # | Sujet | Écran / parcours |`, l'écran nommé comme dans
`docs/vocabulaire.md`. Un nouveau ticket prend le numéro suivant du plus grand
de ce fichier.

## Les règles, en une ligne chacune

Le détail et leurs raisons : § 1 du journal archivé.

| # | Règle |
|---|---|
| R1 | Tout se mesure en **rem** (1 rem = 16 pt), par les tokens de `Tokens.swift` — sauf les traits, en points |
| R2 | Une valeur Figma à 2 pt ou moins d'une taille standard prend la taille standard ; au-delà, elle est gardée et signalée |
| R3 | Figma est la source de vérité : on signale une incohérence, on n'harmonise pas de son côté |
| R4 | Les variables Figma priment sur `agents/design.md`, qui n'en est que le miroir |
| R5 | 390 × 844 est une référence, pas une largeur : chaque écran se vérifie sur SE (375 × 667), Pro Max, et en taille de texte accessible |
| R6 | On ne redessine pas le chrome du système (barre d'état, indicateur d'accueil) |
| R7 | Cibles de 44 pt au moins, Dynamic Type, VoiceOver : l'accessibilité fait partie de la fidélité |
| R8 | Les textes sont recopiés au caractère près, apostrophe typographique `’` comprise ; une faute se signale |
| R9 | On tutoie. Toujours |
| R10 | Les assets viennent de Figma (seule exception : les pictogrammes Lucide des catégories) |
| R11 | Un écran n'est pas fini sans son contrat back-end : la route existe, ou elle s'écrit dans la même PR |
| R12 | Une PR par lot, commits en français à l'impératif |

## Tickets ouverts, écran par écran

Réponses du 06/10/2026 traitées dans la PR `reponses-du-6-octobre`, ajustements
du 08/10/2026 dans `ajustements-du-8-octobre` : tout ce qui y a été réglé,
tranché ou validé a quitté ce fichier.

### Entrée et comptes

| # | Sujet | Écran / parcours |
|---|---|---|
| T124 | Les autocollants Apple et Google de `assets/logos` sont bien des fichiers `.svg`, mais **sans aucun tracé** : chacun embarque la même planche PNG de 345 × 460 px (passeport, valise… Facebook, Apple, Google) dans un `<image>` en base64, et n'en montre qu'un morceau par un `<pattern>`. C'est ce que Figma exporte quand le calque est une image collée, pas une forme. Pour un vrai vectoriel : redessiner (ou vectoriser) les deux autocollants en formes dans Figma, puis « Exporter en SVG » — le fichier doit contenir des `<path>` et aucun `data:image`. `Google Icon2.svg` est vectoriel, mais c'est un G au trait, pas l'autocollant | Entrée |

### Conversation

| # | Sujet | Écran / parcours |
|---|---|---|
| T252 | **Un vocal en pause est jeté** si l'on ouvre les réglages du voyage depuis la conversation : `ChatView.onDisappear` appelle `teardown()`, qui annule l'enregistreur. Garder le vocal en pause (comme un brouillon) au retour dans le fil ? | Conversation — enregistrement |

### Notifications

Voir [`notifications.md`](notifications.md) pour les règles et les choix faits.

| # | Sujet | Écran / parcours |
|---|---|---|
| T242 | **Les textes des notifications sont à relire.** Vérifié le 07/10 : ils ont été réécrits pour le crédit du jour et l'abonnement mensuel le 03/10 (PR #84, #91), et il n'y reste plus un mot de l'ancien modèle (semaines, 1,99 €, déduction, étapes offertes) ; un rappel de renouvellement ne part plus pour un abonnement échu. Si un texte de l'ancien modèle s'affiche encore, c'est un build antérieur au 03/10 : dis lequel. Tous les textes sont dans `backend/src/services/notificationCopy.ts` | Notifications |

### Couvertures

| # | Sujet | Écran / parcours |
|---|---|---|
| T256 | **Les sept gabarits de couverture sont dans l'app** (08/10/2026), redessinés d'après `assets/covers` avec la photo et les mots du voyageur ; la 4e « assortie » est celle de la même famille. Restent trois choix à valider : (1) **les ornements** — la palme d'Assouline, la moto, la route, le globe et le motard de Dessin, les courbes de Photo-dessin — sont **découpés tels quels** dans tes plats (`ios/Tools/import-cover-ornaments.py`), donc les mêmes pour tous les voyages ; les aquarelles et les timbres de ta maquette sont remplacés par les **photos du voyage**. Faut-il des ornements par voyage (générés) ? (2) le dos « Par défaut » montre un trajet stylisé à la place de la carte du pays (elle viendra du gabarit d'impression) ; (3) les polices sont approchées (empattements et grotesque du système, Gloria Hallelujah) : les cadres Figma de chaque plat les donneraient au point près. La composition du PDF qui lit ces choix reste à écrire (T223) | Couvertures |

### Aperçu PDF, partage, commande

| # | Sujet | Écran / parcours |
|---|---|---|
| T193 | La feuille de partage n'a ni « Imprimer » (réservé au PDF) ni « Modifier le ratio image/texte » (plus d'écran où mener). « Partager sur Whatsapp » n'apparaît que si WhatsApp est installé | Partager |
| T255 | **Trois promesses que le code ne tient pas encore**, retirées de la FAQ en attendant (T202) : le suivi du colis (`trackingUrl` n'est jamais écrit, l'e-mail « carnet expédié » n'est envoyé par aucun code), le contrôle de la qualité des photos (`photoAnalysis.ts` calcule résolution et flou, mais rien ne l'appelle), et l'archivage à 5 ans (aucune tâche) | Commande, photos, données |

### Exemples de carnets

| # | Sujet | Écran / parcours |
|---|---|---|
| T236 | La galerie : les cartes ne s'ouvrent pas (pas d'écran ni de route pour lire un carnet public), et le résumé et les catégories des vrais carnets ne sont écrits que par le seed — filtres vides | Exemples de carnets |
| T43 | Aucune photo de couverture ne remonte dans les exemples de carnets : la mosaïque est à revoir sur de vraies images | Exemples de carnets |

### Profil et abonnement

| # | Sujet | Écran / parcours |
|---|---|---|
| T69 | Les cartes d'options divergent (rayon 8 / 14 / 12 contre 16 / 8 / 8 sur la feuille du moyen de paiement) pour le même motif. À harmoniser dans Figma | Abonnement |

### Aide, FAQ, textes légaux

| # | Sujet | Écran / parcours |
|---|---|---|
| T203 | Le chapitre 2 de la politique de confidentialité décrit **le site** (Google Analytics, Hotjar, pixel Meta, cookies Webflow), pas l'app, et ne dit pas ce qu'elle collecte (enregistrements, photos, positions). À réécrire avec les étiquettes de la fiche App Store. Sa liste de destinataires ne nomme ni OpenAI, ni Anthropic, ni Stripe, ni APITemplate, et elle ne dit pas les 5 ans de conservation que la FAQ annonce | Politique de confidentialité |
| T195 | « Hotter Ltd » lu **Hotjar Ltd** dans les prestataires. À confirmer | Politique de confidentialité |

### Partout

| # | Sujet | Écran / parcours |
|---|---|---|
| T253 | **Textes écrits sans maquette, à relire** (06-07/10) : la bulle de MEMO pour les notifications (T246 : « Suggestions », « Active les notifications pour que je t’aide à tenir le rythme que tu t’es fixé : je te ferai signe quand il sera temps de raconter la suite. », et sa version « coupées… Active-les dans les Réglages… », boutons « Activer les notifications » / « Activer dans les Réglages ») ; l'abonnement au renouvellement coupé (« Jusqu’au 12 octobre », « Tu racontes sans limite jusqu’au … grâce à ton abonnement », « Ton abonnement ne se renouvellera pas : tu racontes sans limite jusqu’au …, puis tu retrouves les 5 minutes du jour. ») ; les échecs d'envoi du support et des votes (« Pas de réseau : ton message n’est pas parti… », « Tu nous as déjà beaucoup écrit aujourd’hui… ») ; « Paiement abandonné, commande non finalisée » / « Finaliser ma commande » ; une trentaine de réponses de la FAQ réécrites pour dire ce que l'app fait (T202) ; **et du 08/10** : « Ça peut prendre quelques minutes. » sous l'étape de la composition, la pastille « À venir », « 3 min 20 restantes » / « Épuisé » sur la ligne du crédit du jour, les deux réponses de MEMO à un message trop court (« « ok » : c’est un peu court, je n’ai pas compris ce que tu voulais me dire. Tu peux m’en dire un peu plus ? » et « Je n’ai pas réussi à en tirer un souvenir : « … », c’est trop court pour moi. Raconte-moi ce qui s’est passé, avec tes mots. »), le titre du dos « Dessin » (« La route continue… », repris de ta maquette) | Partout |

### Hors de l'app : paiements, e-mails, site

| # | Sujet | Écran / parcours |
|---|---|---|
| T229 | **Apple Pay : trois gestes, dans cet ordre**, pour chaque compte Stripe (le sandbox et la production ont chacun le leur). (1) Stripe ▸ Paramètres ▸ Moyens de paiement ▸ Apple Pay ▸ « Ajouter une nouvelle application » : télécharger la demande de certificat (CSR). (2) Portail Apple ▸ Identifiers ▸ Merchant IDs ▸ `merchant.com.tonapp.memobook` ▸ Apple Pay Payment Processing Certificate ▸ Create : déposer la CSR, télécharger le `.cer` et le rendre à Stripe. (3) Railway ▸ `api` ▸ `APPLE_PAY_MERCHANT_ID=merchant.com.tonapp.memobook`. C'est le serveur qui allume Apple Pay dans la feuille de Stripe, sans nouveau build ; dans l'autre ordre, le bouton paraît et le paiement échoue après Face ID. Voir `docs/paiements.md` | Commande — paiement |
| T250 | **Le produit mensuel reste à poser chez Apple et chez Stripe** : `com.memobook.app.subscription.monthly` à 4,99 € dans App Store Connect (groupe « MemoBook »), l'hebdomadaire retiré de la vente sans être supprimé ; chez Stripe, le prix `memobook_subscription_monthly` est créé dans le bac à sable (`price_1UMIMLBknFHnQoHL2aPelZqm`, 03/10/2026), `memobook_subscription_weekly` et `memobook_memory_upgrade_weekly` restent à désactiver à la main (le sandbox refuse les `update` à Claude), et le prix mensuel à créer dans le compte de production le jour où il existera. Voir `docs/paiements.md` | Abonnement, paywall |
| T251 | **Le pied de l'offre du paywall laisse voir les cartes en très grand texte** (déjà le cas sur `main` avant le crédit du jour, relevé à la recette du 03/10/2026) : en AX XL, le texte des cartes se lit sous les lignes du pied à travers le voile `BrandFooterScrim` (aplat à 90 %), et le bas d'une carte dépasse sous « S’abonner » tant que l'offre n'est pas défilée. Au repos, sur iPhone 17, « Conditions d’utilisation » et « Confidentialité » sont estompés par le même voile dans la version découverte (titre sur trois lignes). Le voile est celui de toute l'app : à trancher — aplat plein sous le pied du paywall seulement, ou liens remontés au-dessus du voile | Paywall |
| T133 | La feuille d'ajout de carte s'ouvre **par-dessus** (paywall, profil, commande) : trois écarts à « une feuille ne s'empile pas ». Si Clara les accepte, la règle devient « une feuille ne s'empile que pour aller voir et revenir » | Paiement |
| T204 | L'e-mail de réinitialisation arrive en indésirables : SPF, DKIM, DMARC et le sous-domaine `tx.memo-book.com` à poser chez Resend et au registrar (ex-T145). Même domaine, même sort pour l'e-mail « Tes données MemoBook sont prêtes » (01/10/2026) | Entrée — mot de passe oublié, Profil — export |
| T254 | Les conditions d'utilisation et la politique de confidentialité de l'app sont à republier **à l'identique** sur memobook.fr (reste de T247) | Site |

### En pause — v2

| # | Sujet | Écran / parcours |
|---|---|---|
| T33 | La carte du voyage | Accueil d'un voyage |
| T76 | « La carte » et « Connecte ton Tricount » des réglages, et les six connecteurs du profil : dessinés, ne branchent rien — affichés « À venir », pâlis, depuis le 08/10/2026 | Réglages du voyage, Profil |
