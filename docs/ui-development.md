# Interface iOS — ce qui reste à régler

Ce fichier ne garde que ce qui **attend encore une réponse** : les tickets
ouverts, écran par écran, et les constats de la dernière recette. Il faisait
4 165 lignes ; tout ce qui était réglé — fiches écran, lots, réponses aux
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

## Recette du 30/09/2026

L'app a été parcourue écran par écran dans le bac à sable (`-previewSignedIn`),
par un parcours automatisé qui photographie chaque écran : iPhone 17 en texte
standard, iPhone 17 en très grand texte (Accessibility XL), iPhone SE. Et le
code a été relu route par route contre le back-end. Ce qui suit est ce qui
reste ; ce que la recette a déjà réparé est à la fin de la section.

### Interface — à corriger ou à trancher

| # | Sujet | Écran / parcours |
|---|---|---|
| T210 | **Le texte passe sous l'heure et la batterie** en défilant, sans voile : profil, réglages du voyage, cagnotte, commande, aperçu, support, accueil. Les écrans à photo pleine page (voyage, entrée, paywall) sont faits pour ça, les autres non. Proposition : un voile crème de la hauteur de la barre d'état, écran par écran — à valider dans Figma | Partout |
| T211 | **Vouvoiement restant** (R9) : « Écrivez l'aventure à plusieurs » (Nouveau carnet › Rejoins une aventure), « Personnaliser vos carnets » et « Rendez chaque carnet unique » (Commande, étape 3/7). Avec T188, c'est tout ce qui reste hors textes légaux (T203) | Nouveau carnet, Commande |
| T212 | **Une trentaine de textes ont l'apostrophe droite** `'` au lieu de `’` (R8) : l'écran d'entrée (« Crée ton journal de voyage à l'oral… », « Nous allons t'accompagner »), les erreurs réseau, la demande de micro, les messages des couvertures… Correction mécanique, d'un bloc, si tu la valides | Partout |
| T213 | **Majuscules à l'anglaise** : « Commander mon Carnet », « Méthode de Paiement », « Ma Cagnotte » (l'en-tête, alors que la ligne du profil dit « Ma cagnotte »), « On compose ton Carnet », « Ton Carnet prend forme ». Recopiées de Figma (R8) : à trancher une fois, pour tout le monde | Commande, cagnotte, aperçu, conversation |
| T214 | « **Nmb** de pages » (onglet des personnalisations) : « Nb de pages », ou « Pages » ? | Personnalisations |
| T215 | Le champ de l'inscription dit « Email » ; partout ailleurs c'est « E-mail » | Entrée — inscription |
| T216 | Récapitulatif : la ligne de sous-total (« 129,50 € » sous « Livraison ») n'a pas de libellé | Commande 5/7 |
| T217 | Le tunnel annonce « **50 pages · environ 89,90 €** » à l'étape 1, puis « **80 pages · 129,50 €** » au récapitulatif, sans dire pourquoi (pages projetées contre pages composées). Vu dans le bac à sable ; à revoir sur un vrai voyage | Commande |
| T218 | « Équilibre parfait » et « 50 / 50 » en bleu clair sur le crème : trop pâle pour se lire | Personnalisations — ratio |
| T219 | Pendant la composition, « Commander sans attendre la composition » est presque invisible, et les morceaux de la page qui se monte **débordent à droite** de son cadre (iPhone 17 et SE) | Aperçu PDF — composition |
| T220 | La vignette de « Prévisualisation PDF » est un livre gris vide, pas une miniature du carnet | Réglages du voyage |
| T221 | « Rejoint par 12 000+ voyageurs » : en grand texte, « 12 » et « 000+ » se séparent (il manque l'espace insécable) | Entrée |
| T222 | Le **bac à sable se contredit** : « Bienvenue Camille » à l'accueil, « Maylis Garde » au profil ; le voyage en cours du profil (10/12/2026 – 02/01/2027) n'est pas celui de l'accueil. Sans effet en production, mais la recette s'y perd | Bac à sable |

### Ce qui manque côté back-end

Relevé en lisant le code, route par route ; les cinq premiers sont vérifiés
ligne à ligne. Les 62 routes que l'app appelle **existent toutes** côté serveur :
rien n'est cassé dans le contrat. Ce qui manque, ce sont des routes et des
tâches qui n'ont jamais été écrites.

| # | Sujet | Écran / parcours |
|---|---|---|
| T223 | **La génération du carnet ignore les personnalisations et les couvertures.** `jobs/structure.ts` ne transmet que titre, sous-titre, auteurs, thème et photo de couverture : ratio, polices, quiz, zones libres, mots fléchés, anecdotes, cadres, nombre de pages, style et textes des couvertures sont enregistrés… et jamais lus | Personnalisations, couvertures |
| T224 | **Aucun écran ne lance la composition.** `POST /v1/memos/:id/renders` n'est appelé que par un ancien écran que plus rien n'ouvre. Même branché (T194), l'aperçu attendrait donc à jamais ; et « Payer » ne fait **rien, sans rien dire**, tant qu'aucun rendu n'existe | Aperçu PDF, commande |
| T225 | **Une carte ajoutée dans le tunnel est refusée** : elle reçoit un identifiant local, envoyé comme `paymentCardId`, et le serveur répond « Ce moyen de paiement est introuvable ». Aucune route ne crée de moyen de paiement (profil et paywall aussi : les cartes vivent en mémoire) | Commande, profil |
| T226 | **« Envoyer » du support ne part nulle part** : l'écran attend 600 ms et dit « envoyé ». Aucune route. « Partager mes retours » (mot des fondateurs) mène au même formulaire, et les votes « cette réponse t'a aidé » sont perdus | Support, FAQ |
| T227 | **Les étapes, les compteurs et la destination d'un voyage ne sont écrits que par le seed.** Aucune route ni tâche ne crée d'étape (`memo_steps`), ni n'écrit souvenirs, pages, jours, km, photos, destination. Sur un vrai voyage : section « Étapes » vide, « 0 souvenir », chiffres du dos de couverture vides, pas de drapeau | Accueil, voyage, couvertures |
| T228 | **Le bouton imprimante des voyages passés n'apparaît jamais** : rien n'écrit `memos.isPrintable`, pas même la fin d'un rendu | Accueil |
| T229 | La commande : « Recevoir sur WhatsApp » n'appelle pas `POST /v1/orders/:id/whatsapp` ; le lien partagé de la confirmation est un lien mort (`/c/<uuid>` au lieu du vrai lien) ; Apple Pay est proposé, mais n'apparaît pas dans la feuille de Stripe : l'identifiant marchand existe et l'app le porte depuis le 02/10, il reste le certificat Apple Pay côté Stripe et `applePayMerchantId` à passer | Commande — confirmation, paiement |
| T230 | **Un proche ne peut pas contribuer** : le lien de la cagnotte mène à `/c/<lien>`, mais aucune page publique ne prend un don | Cagnotte |
| T232 | Le suivi des commandes liste aussi les commandes dont le paiement a été abandonné (`draft`), comme si elles allaient partir | Profil — suivi des commandes |
| T233 | Un **co-voyageur voit « Supprimer le voyage »** (réglages et tiroir de l'accueil), et le serveur lui répond 404. Il manque un `canDelete`, comme `canClearConversation` | Réglages du voyage, accueil |
| T235 | On ne peut pas **supprimer un souvenir** (`DELETE /v1/entries/:id` existe, l'app ne l'appelle pas), ni une photo de couverture importée | Conversation, couvertures |
| T236 | La galerie : les cartes ne s'ouvrent pas (pas d'écran ni de route pour lire un carnet public), et le résumé et les catégories des vrais carnets ne sont écrits que par le seed — filtres vides | Exemples de carnets |
| T237 | Les photos de la conversation proposées pour une couverture passent par un lien signé d'une heure : l'écran laissé ouvert plus longtemps montre des images cassées | Couvertures |

### Déjà corrigé par la recette

Dans la PR de ce lot, vérifié en simulateur :

- **La conversation tournait à 100 % d'un cœur sur iPhone SE**, ouverte et au
  repos : la mesure du défilement (un `GeometryReader` en fond de la liste)
  faisait se replacer la liste sans fin. Remplacée par une lecture de
  l'`UIScrollView` (`brandScrollOffset`) : 0 %. La bannière « Ton Carnet prend
  forme » ne compte plus que les défilements au doigt — celui de l'ouverture la
  rappelait pour de bon.
- **« Statistiques » du profil ne s'ouvrait plus** : la ligne était revenue sur
  une action vide ; la feuille existait.
- **T207** — le fil s'ouvre plus tôt pour la puce en vol (un quart de seconde,
  de la hauteur d'une ligne), la barre garde la place de ses suggestions
  pendant que MEMO répond, et l'atterrissage ne fait plus plonger le fil.
- **Le scotch des cartes de l'accueil** était tranché au ras de la carte :
  le tiroir de glissé rognait haut et bas.
- **« Supprimer la photo »** restait inaccessible quand l'accès aux photos
  était refusé.
- **T200** — la carte de l'écran d'entrée tient sur un iPhone SE : vue, et non
  plus seulement mesurée.
- **Très grand texte** : la pastille « étapes restantes » sortait de l'écran,
  « Enregistrer » se coupait lettre par lettre dans le chat, et la ligne
  « Limites de souvenirs » coupait ses mots en deux.

## Tickets ouverts, écran par écran

### Entrée et comptes

| # | Sujet | Écran / parcours |
|---|---|---|
| T191 | Titres recopiés à l'anglaise : « Ton Nom et Prénom », « Ta Date de Naissance », « Ton Numéro Whatsapp » (et « Whatsapp »). Le repère « XX/XX/XXXX » se lirait mieux « JJ/MM/AAAA » ? | Dernières questions |
| T192 | La flèche du premier écran ramène à l'écran d'entrée, ce qui ferme la session tout juste ouverte. À garder, ou à retirer du premier écran ? | Dernières questions |
| T124 | Les autocollants Apple et Google sont encore des **images** dans `assets/logos` (un bitmap dans un `<pattern>`, aucun tracé) : les exports vectoriels annoncés le 26/09 ne sont pas arrivés sur GitHub | Entrée |

### Accueil

| # | Sujet | Écran / parcours |
|---|---|---|
| T168 | Le tiroir des cartes (croix, flèche, imprimante cerclées) n'a pas de maquette. À dessiner, ou à valider tel quel | Accueil |
| T170 | La boîte hors ligne parle de « vocal » alors que la file porte aussi les textes et les photos : « Ton vocal enregistré hors ligne est bien conservé » après un texte. Généraliser le libellé dans Figma d'abord | Accueil — hors ligne |
| T196 | Le flou (16) et le voile (18 %) de la carte « à venir » sont relevés sur l'export : aucune variable Figma derrière | Accueil — voyage à venir |
| T238 | Un voyage qu'on vient de créer **sans dates** se range en bas de « Tes voyages », pas en grande carte : la grande carte va au voyage commencé le plus récemment, et un voyage sans date passe après tous les autres (même règle que pour un voyage du serveur). Le mettre en tête juste après sa création ? | Accueil — Tes voyages |
| T240 | Créé hors ligne, le voyage montre sa barre d'attente à la place du code **jusqu'à la reconnexion**, sans un mot — comme demandé : seul le code attend, « Partager » reste gris. Ajouter une ligne (« Ton code arrivera dès ta reconnexion ») ou garder la barre seule ? | Création — co-voyageurs |

### Conversation

| # | Sujet | Écran / parcours |
|---|---|---|
| T205 | La puce en vol se pose dans le creux que le fil lui ouvre, puis le fil **monte d'une ligne** au moment où les trois points de MEMO apparaissent dessous (vu en vidéo le 30/09). Et sur un libellé de deux lignes, le raccord se voit d'un point ou deux. Faire la place des trois points dès le décollage, ou un `matchedGeometryEffect` au pixel — à décider si ça vaut le coût | Conversation |
| T249 | Le **bandeau d'avertissement** de la barre d'enregistrement n'a pas de maquette : rouge doux (`MemoBookColor.errorSoft`, la version douce de Danger de `agents/design.md`, `#FBDDDD`) au-dessus de la barre à 30 s du bout du crédit du jour, compte à rebours « Plus que 30 secondes avant la limite du jour », pulsation de la taille à 5 s, état « Crédit du jour épuisé » tapable vers le paywall. À dessiner, ou à valider tel quel — la variable Figma du rouge doux comprise (R4) | Conversation — enregistrement |
| T208 | Le micro de la bulle vocale : nu et vert au pied du rond dans `3627:31695`, en pastille détourée dans l'app (Clara, 26/09). À départager | Conversation |

### Notifications

Voir [`notifications.md`](notifications.md) pour les règles et les choix faits.

| # | Sujet | Écran / parcours |
|---|---|---|
| T242 | **Les textes des notifications sont à relire** : la feuille Notion donne l'objectif et le ton, pas les mots. Ils sont tous dans `backend/src/services/notificationCopy.ts` (fin de voyage, relance d'écriture, carnet pas commandé, vacances, l'an dernier, anniversaire). Ceux de « Nouveau récit » et du point de la semaine, bulles comprises, sont validés | Notifications |
| T245 | Quand tout est coupé dans les Réglages d'iOS, la feuille « Notifications » le dit et propose « Ouvrir les réglages ». **Ni le message ni le bouton ne sont dans `3023:15042`** : à dessiner, ou à valider tels quels | Réglages — notifications |
| T246 | La maquette dessine une bulle de MEMO « Suggestions - activer les notifs » avec un bouton « Activer notif » dans la conversation. Pas faite : l'autorisation se demande à l'étape « Notifications » de la création. La garder pour qui a passé l'étape ? | Conversation |

### Réglages du voyage et personnalisations

| # | Sujet | Écran / parcours |
|---|---|---|
| T239 | Tant que le serveur n'a pas reçu un voyage créé hors ligne, ses **réglages**, « Inviter un proche », l'aperçu et la commande ne s'ouvrent pas : ils lisent le serveur, et montrent son erreur. Les griser avec une phrase (« disponible dès ta reconnexion »), ou les ouvrir sur le brouillon ? | Réglages du voyage — hors ligne |
| T248 | La ligne et la feuille « **Crédit du jour** » n'ont pas de maquette : la ligne reprend la coque des lignes d'à côté avec une jauge toujours visible (vert, rouge à zéro), la feuille dit le reste du jour, sa valeur à l'écrit, les trois règles (partage, ce qui consomme, recharge à minuit) et « Passer en illimité » en lime ; « Illimité » et un paragraphe pour un abonné. À dessiner dans Figma, ou à valider tel quel | Réglages du voyage — crédit du jour |
| T164 | Les « Valider » des feuilles de personnalisation semblent inutiles à Clara. Sans bouton, la feuille se referme au choix ; avec, elle reste ouverte. À trancher avec Hugo et Paul | Personnalisations |
| T197 | Plus rien ne mène aux couvertures depuis les personnalisations (la V3 ne dessine pas la ligne). Il reste « Configurer » sur l'aperçu PDF. À valider, ou une sixième pastille | Personnalisations |
| T199 | Les assortiments de typographies : la V3 écrit « La recommandations de nos équipes » (sic), et l'app le recopie. Corriger en « La recommandation » ? | Personnalisations — typographies |

### Couvertures

| # | Sujet | Écran / parcours |
|---|---|---|
| T144 | Quel style porte une photo ou un texte, c'est l'app qui le décide (`CoverTreatment.carriesPhoto`, `carriesText`). À valider avec Clara, et à servir par le serveur le jour où le catalogue des styles y vivra | Couvertures |
| T138 | Le champ des textes remonte après 350 ms, le temps que le clavier monte — une durée choisie. La parade propre écoute la hauteur du clavier (`keyboardLayoutGuide`) | Couvertures — textes |

### Aperçu PDF, partage, commande

| # | Sujet | Écran / parcours |
|---|---|---|
| T194 | **L'aperçu PDF est sur le jeu d'essai** : « Rome et la Dolce Vita » pour tout le monde, pas de PDF. `GET /v1/memos/:id/preview` existe ; le brancher demande de décider **quand une composition se lance** (`POST /v1/memos/:id/renders`, payante) | Aperçu PDF |
| T193 | La feuille de partage n'a ni « Imprimer » (réservé au PDF) ni « Modifier le ratio image/texte » (plus d'écran où mener). « Partager sur Whatsapp » n'apparaît que si WhatsApp est installé | Partager |
| T130 | « Commander le carnet » ouvre le tunnel même sans carnet composé : c'est `order-context` qui répond. À vérifier sur un voyage sans rendu | Commande |

### Cagnotte

| # | Sujet | Écran / parcours |
|---|---|---|
| T186 | La carte ne se saisit pas dans la page (la maquette a numéro, expiration, CVV) : elle se tape dans la fenêtre de Stripe. Des champs intégrés sont possibles, mais c'est un autre flux de paiement | Ajouter à ma cagnotte |
| T187 | « Don récurrent » est pâli : le serveur ne sait pas prélever chaque mois | Ajouter à ma cagnotte |
| T188 | « Votre contribution » vouvoie (R9) : à réécrire dans Figma | Ajouter à ma cagnotte |
| T189 | « Prix moyen d'un carnet » est devenu « Coût estimé de ton carnet » (l'estimation de ce carnet-là). À valider, ou donner un prix moyen | Ajouter à ma cagnotte |
| T190 | La maquette ne dessine pas d'en-tête ; l'app pose une flèche et « Ajouter à ma cagnotte » | Ajouter à ma cagnotte |
| T201 | « Ajouter » et « Partager » de la cagnotte : rien ne les désactive dans le code, et la recette les montre actifs. S'ils te paraissent encore inertes sur ton téléphone, c'est autre chose — à revoir avec la trace réseau | Ma cagnotte |

### Profil et abonnement

| # | Sujet | Écran / parcours |
|---|---|---|
| T209 | Le genre deviné est une liste d'environ 600 prénoms ; un prénom absent (ou mixte) accorde au masculin (« Abonné »). *(Portait par erreur le numéro T170, déjà pris.)* | Profil |
| T169 | La feuille « Genre » n'a pas de maquette | Profil |
| T241 | La feuille « **Exporter mes données** » n'a pas de maquette : une proposition (ce que contient l'archive, l'adresse où part le lien, « M'envoyer le lien ») puis une confirmation (la coche du support, « Regarde ta boîte mail »). À dessiner, ou à valider telle quelle — mots compris | Profil |
| T159 | Les lieux et rencontres des **Statistiques** ne comptent que les souvenirs rédigés depuis le 18/09 : les vieux voyages sont sous-comptés. Relancer une relecture générale (quelques centimes d'IA par souvenir) ? | Statistiques |
| T161 | La feuille « Statistiques » n'a été vue que sur iPhone 17 (texte moyen et AX3) : à regarder sur SE, où elle doit défiler | Statistiques |
| T69 | Les cartes d'options divergent (rayon 8 / 14 / 12 contre 16 / 8 / 8 sur la feuille du moyen de paiement) pour le même motif. À harmoniser dans Figma | Abonnement |

### Paywall

| # | Sujet | Écran / parcours |
|---|---|---|
| T247 | **Les textes du nouveau modèle sont à valider avec Clara** (03/10/2026) : les écrans du paywall (découverte et retour), la bulle « reviens demain » de MEMO et son appel à l'action « Raconter sans limite », le bandeau de la barre d'enregistrement, la ligne et la feuille « Crédit du jour », le paquet « Prix et paiement » de la FAQ. Les CGU et la politique de confidentialité, elles, sont à relire par Hugo et à publier à l'identique sur memobook.fr | Paywall, conversation, réglages du voyage, FAQ |

### Aide, FAQ, textes légaux

| # | Sujet | Écran / parcours |
|---|---|---|
| T202 | Deux réponses de la FAQ contredisent l'app (l'enregistrement rapide ouvre la conversation du premier récit, il n'est pas « ajouté à chacun »). La page fait foi : à trancher, puis à réécrire | FAQ |
| T203 | Le chapitre 2 de la politique de confidentialité décrit **le site** (Google Analytics, Hotjar, pixel Meta, cookies Webflow), pas l'app, et ne dit pas ce qu'elle collecte (enregistrements, photos, positions). À réécrire avec les étiquettes de la fiche App Store | Politique de confidentialité |
| T195 | « Hotter Ltd » lu **Hotjar Ltd** dans les prestataires. À confirmer | Politique de confidentialité |

### Partout

| # | Sujet | Écran / parcours |
|---|---|---|
| T174 | `Beige Darker` (`#CFBBAA`) est `MemoBookColor.separator`, et il sert à 22 endroits (séparateurs, scotch, filets Apple/Google). Veut-on plus clair ? Une ligne dans `Tokens.swift` et la variable Figma | Partout |
| T143 | Blocs **sans maquette**, écrits sur les motifs existants : assortiments, recherche du support, messages d'information des couvertures, « Bientôt disponible », « Commander sans attendre », « Supprimer la conversation » et sa feuille (ex-T185) | Partout |
| T121 | L'icône « Renvoyer » emprunte `IconTeleverser`, faute d'un envoi dans le jeu de marque | Création — invitation |

### Hors de l'app : paiements, e-mails

| # | Sujet | Écran / parcours |
|---|---|---|
| T250 | **Le produit mensuel reste à poser chez Apple et chez Stripe** : `com.memobook.app.subscription.monthly` à 4,99 € dans App Store Connect (groupe « MemoBook »), l'hebdomadaire retiré de la vente sans être supprimé ; chez Stripe, le prix `memobook_subscription_monthly` est créé dans le bac à sable (`price_1UMIMLBknFHnQoHL2aPelZqm`, 03/10/2026), `memobook_subscription_weekly` et `memobook_memory_upgrade_weekly` restent à désactiver à la main (le sandbox refuse les `update` à Claude), et le prix mensuel à créer dans le compte de production le jour où il existera. Voir `docs/paiements.md` | Abonnement, paywall |
| T133 | La feuille d'ajout de carte s'ouvre **par-dessus** (paywall, profil, commande) : trois écarts à « une feuille ne s'empile pas ». Si Clara les accepte, la règle devient « une feuille ne s'empile que pour aller voir et revenir » | Paiement |
| T204 | L'e-mail de réinitialisation arrive en indésirables : SPF, DKIM, DMARC et le sous-domaine `tx.memo-book.com` à poser chez Resend et au registrar (ex-T145). Même domaine, même sort pour l'e-mail « Tes données MemoBook sont prêtes » (01/10/2026) | Entrée — mot de passe oublié, Profil — export |

### En pause — v2

| # | Sujet | Écran / parcours |
|---|---|---|
| T33 | La carte du voyage | Accueil d'un voyage |
| T76 | « La carte » et « Connecte ton Tricount » des réglages : dessinées, n'ouvrent rien | Réglages du voyage |
| T43 | Aucune photo de couverture ne remonte dans les exemples de carnets : la mosaïque est à revoir sur de vraies images | Exemples de carnets |
