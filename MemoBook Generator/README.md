# MemoBook Generator

L'outil d'établi qui compose un carnet **à la main, en attendant l'app** : on
dépose un dossier de vocaux WhatsApp, ils sont transcrits, le récit est découpé
en étapes, et il en sort le JSON du carnet — voire le PDF.

```bash
"./MemoBook Generator/atelier.sh"
```

Le navigateur s'ouvre sur <http://127.0.0.1:4173>. Rien à installer : Node
suffit, et la transcription passe par `transcribe-whatsapp.sh`, qui ne demande
que `curl`.

Il tourne aussi **sans rien installer du tout**, sur
<https://hugo-jouffre.github.io/memo-book/> — voir « Deux façons de le faire
tourner » plus bas.

## Ce qu'il y a dans ce dossier

| Fichier | Rôle |
|---|---|
| `atelier.sh` | Lance le serveur local et ouvre le navigateur |
| `transcribe-whatsapp.sh` | La transcription, en ligne de commande. **C'est lui qui travaille**, même quand l'appel vient de la page |
| `server.mjs` | Le serveur local : sert la page, lance le script, relaie les appels de modèle |
| `public/` | La page elle-même — c'est ce dossier qui est publié en ligne |
| `public/partage.js` | Ce qui doit rester identique en local et en ligne : renommage, format du fichier groupé, consigne de découpage |
| `public/moteur-navigateur.js` | La transcription sans serveur, pour la version hébergée |
| `templates/travel-journal/` | Le gabarit du PDF envoyé à APITemplate — voir plus bas et [`docs/apitemplate.md`](../docs/apitemplate.md) |
| `TRANSCRIPTION.md` | Le script en ligne de commande : options, coût, alternative gratuite en local |

## La boucle de travail

1. **Clé API OpenAI** — dans la boîte « Clés et réglages ». Elle reste dans le
   navigateur (décoche « Retenir » pour ne pas la garder) et n'est envoyée
   qu'au serveur local, qui la passe au script. Champ laissé vide : le serveur
   cherche `OPENAI_API_KEY` dans l'environnement, puis `.env`, puis
   `backend/.env` — la même résolution que le script.
2. **Dépose les vocaux.** Les `Voice message.ogg.oga` sont acceptés tels
   quels ; ils sont **renommés en `.ogg`** avant d'être envoyés à Whisper, et
   la liste affiche le nom réellement transcrit.
3. **Transcrire.** La sortie du script défile en direct, `[03/12] Voice
   message (2).ogg` compris. **Dès qu'un vocal est transcrit, il est rangé** :
   le récit complet repasse au modèle, qui le découpe en étapes, les titre,
   les situe et les date. Il n'y a pas de boîte « à classer » — un souvenir
   n'attend jamais qu'on s'occupe de lui.
4. **Le carnet se déduit tout seul** : titre, destination, dates, voyageurs.
   Une petite étoile `✦` à côté d'un libellé signale une valeur trouvée par le
   modèle ; dès que tu écris dedans, le champ devient tien et plus rien ne
   l'écrase. La date de **retour** suit la dernière étape tant que tu n'y as
   pas touché : un voyage en cours avance sans qu'on y pense.
5. **Relis les « Étapes groupées »** — le carnet entier dans un seul champ,
   étape par étape. Corrige, puis **Applique aux étapes**. Les crochets
   `[Voice message.ogg]` rattachent chaque texte à son vocal ; garde-les, ainsi
   que les lignes `## …`, pour que les corrections retournent au bon endroit.
   **Redécouper avec l'IA** refait le découpage complet.
6. **Ajuste à la main** — glisser-déposer entre étapes, réordonner, corriger.
   Chaque étape porte quatre outils : monter, descendre, **dupliquer** et
   supprimer. La duplication recopie souvenirs et photos avec de nouveaux
   identifiants : modifier la copie ne touche pas l'original.
7. **Génère le JSON** — le bouton passe à « Génération en cours… », puis la
   fenêtre d'enregistrement s'ouvre. Le panneau du bas montre ensuite ce qui
   vient d'être écrit.
8. **Génère le carnet** *(Beta)* — le JSON part chez APITemplate, sur le
   template de `templates/travel-journal/`, et le PDF s'ouvre dans un onglet.

### Garder le gabarit à jour côté APITemplate

APITemplate ne lit pas `templates/travel-journal/` directement : il garde sa
propre copie de `index.html` et `style.css`, poussée par
`POST /update-template`. Deux façons de la mettre à jour :

- **`.github/workflows/sync-apitemplate.yml`**, automatiquement à chaque
  `push` sur `main` qui touche le template — s'il porte le secret
  `APITEMPLATE_API_KEY`.
- **Le bouton « Synchroniser le gabarit depuis GitHub »**, dans « Clés et
  réglages ». Il récupère `index.html`, `style.css` et `fonts.css` sur GitHub
  (branche `main`) et les pousse avec la clé déjà collée dans les réglages —
  utile si le secret côté CI n'est pas posé.

Dans les deux cas, `templates/travel-journal/` reste l'unique source de
vérité : ce qu'il contient est ce qui part chez APITemplate, tel quel.

### Sauvegarder et reprendre

Les deux petites icônes de l'en-tête enregistrent l'avancement dans un fichier
`…memobook.json`, et le relisent pour reprendre exactement où on en était :
étapes, textes, photos, titres, dates, voyageurs, rencontres.

Deux choses n'y sont **pas**, volontairement :

- **les clés d'API** — ce fichier a vocation à circuler, pas elles ;
- **les vocaux** — seul leur texte compte à ce stade, et les embarquer ferait
  un fichier de plusieurs dizaines de mégaoctets. Au retour, les enregistrements
  ne sont plus écoutables ; tout le texte est là.

C'est le seul moyen de survivre à un rechargement de page : l'état vit en
mémoire, il n'y a pas de base de données.

Le bandeau de statistiques au-dessus suit le voyage au fur et à mesure :
étapes, jours couverts, lieux, personnes rencontrées, vocaux, temps de voix,
photos, mots. Survole une tuile pour voir le détail — les lieux, les prénoms.

### Voyageurs et rencontres

Le modèle sépare deux listes, et les **cumule** d'un vocal à l'autre :

- les **voyageurs**, celles et ceux qui font le voyage, alimentent le champ du
  même nom ;
- les **rencontres**, les personnes croisées et nommées en chemin, alimentent
  la statistique « rencontrées ».

Le cumul compte : quelqu'un nommé dans le premier vocal et jamais recité ne
disparaît pas au douzième. Une personne qui passe du statut de rencontre à
celui de compagnon de route quitte la seconde liste pour la première. Les deux
listes connues sont renvoyées au modèle à chaque passe, pour qu'il complète au
lieu de recommencer.

Les étapes 2 et 3 sont facultatives : un dossier déjà transcrit, une
conversation WhatsApp collée, ou des étapes posées à la main marchent aussi.

### Ce qui reste à sa place

Un vocal déjà transcrit n'est pas redéposé quand on relance : le serveur
reconnaît le même fichier au nom et à la taille et l'écrase au lieu de le
cloner. Une relance ne coûte donc rien et ne duplique rien.

### La date d'une photo se lit dans son nom

WhatsApp réécrit la date de modification au téléchargement : une photo prise en
juillet arrive datée d'aujourd'hui, et se rangerait dans la mauvaise étape. Le
**nom du fichier** est donc lu en premier, et la métadonnée ne sert que de
secours. Les formes reconnues couvrent ce qui circule en pratique :

| Nom | Date retenue |
|---|---|
| `Nom conv WhatsApp - 2026-08-27 11.26.10 (1).jpg` | 2026-08-27, 11:26 |
| `IMG-20260827-WA0003.jpg` | 2026-08-27 |
| `PXL_20260827_112610123.jpg`, `IMG_20260827_112610.jpg` | 2026-08-27, 11:26 |
| `WhatsApp Image 2026-08-27 at 11.26.10.jpeg` | 2026-08-27, 11:26 |
| `Photo 27-08-2026 à 11.26.jpg` | 2026-08-27, 11:26 |
| `IMG_4821.HEIC` | aucune — retour à la métadonnée |

La date lue s'affiche sous chaque vignette ; un `~` signale qu'elle vient de la
métadonnée, donc qu'elle est à vérifier. Une date de fichier qui n'existe pas
(`2026-13-45`) est ignorée plutôt que devinée.

Le découpage relit **tout** le récit à chaque nouveau vocal — un vocal arrivé
après coup peut appartenir à une étape déjà écrite, ou la couper en deux. Les
titres, lieux et dates écrits à la main sont repassés au modèle et repris tels
quels ; les photos suivent leur étape.

## Deux façons de le faire tourner

| | En local (`./atelier.sh`) | En ligne (GitHub Pages) |
|---|---|---|
| Transcription | `transcribe-whatsapp.sh` | La page appelle OpenAI directement |
| Cache des transcriptions | Sur le disque, survit à tout | En mémoire, perdu au rechargement |
| Dossier du disque | Oui | Non — il faut déposer les fichiers |
| Clé d'API | Champ, ou `.env` de la machine | Champ uniquement |
| Où va la clé | Au serveur local, puis au script | Du navigateur à OpenAI, sans intermédiaire |

La page **détecte toute seule** où elle tourne : si `/api/config` répond, c'est
le mode local ; sinon elle bascule en mode navigateur. Rien à configurer.

L'interface, le découpage, le classement et l'export sont identiques. Le
renommage des vocaux, le format du fichier groupé et la consigne envoyée au
modèle vivent dans [`public/partage.js`](public/partage.js), chargé par les
deux côtés : une seule copie, une seule vérité.

Le mode navigateur ([`public/moteur-navigateur.js`](public/moteur-navigateur.js))
réimplémente le strict nécessaire du script — renommage, tri par date, limite
de 25 Mo, réessais sur les `429`, cache — et rien de plus. **Le script reste la
référence** : quand les deux divergent, c'est lui qui a raison.

### Ce qui part en ligne, et ce qui n'y va pas

Le site publié ne contient que des fichiers statiques. **Aucune clé d'API n'y
est stockée, et il ne faut jamais en commiter** : le workflow de publication
refuse de déployer si un `sk-…` traîne dans le dossier. Chaque visiteur colle
la sienne, elle reste dans son navigateur et part directement chez OpenAI.

Corollaire : chacun paie ses propres transcriptions, et personne ne peut
dépenser sur la clé d'un autre.

## Ce que fait le serveur local, et pourquoi il existe

`server.mjs` écoute sur `127.0.0.1` uniquement, sans aucune dépendance npm. Il
sert trois choses que la page ne peut pas faire seule quand elle tourne en local :

| Route | Rôle |
|---|---|
| `POST /api/vocaux/<session>` | Écrit un vocal dans `.atelier/vocaux/<session>/`, sous son nom normalisé, en reposant sa date de fichier |
| `POST /api/transcrire` | Lance `transcribe-whatsapp.sh` et renvoie sa sortie au fil de l'eau (NDJSON) |
| `POST /api/decouper` | Relaie l'appel de découpage vers OpenAI ou Anthropic |

**La transcription n'est pas réimplémentée.** C'est bien
`transcribe-whatsapp.sh` qui travaille : le cache par vocal, les
reprises après coupure, les `429` réessayés et la limite de 25 Mo viennent de
lui. Deux implémentations auraient donné deux comportements à maintenir et
deux factures à débuguer. Corollaire utile : relancer une transcription ne
refacture que les vocaux manquants, et le dossier reste exploitable en ligne
de commande.

### La date de fichier, et pourquoi on la repose

WhatsApp appelle tous les vocaux `Voice message.ogg.oga`, `Voice message
(1).ogg.oga`… Un tri alphabétique placerait `(10)` avant `(2)` : le script
trie donc par date de fichier. Un upload navigateur perd cette date, ce qui
casserait l'ordre du récit — le serveur la repose sur le fichier écrit.

Comme dans le script, c'est la date du **téléchargement**, pas celle de
l'enregistrement. Un coup d'œil à l'ordre des vocaux dans la transcription
groupée reste utile avant de valider.

### Le dossier `.atelier/`

Vocaux déposés et fichiers groupés y atterrissent, à la racine du dépôt. Il
est dans `.gitignore` : rien de tout ça n'a vocation à être commité. Il peut
être effacé à tout moment, au prix d'une retranscription.

## Découpage : OpenAI ou Anthropic

Par défaut le découpage passe par **OpenAI**, avec la clé déjà saisie : une
seule clé suffit pour que l'outil soit complet. Le sélecteur « Découpage en
étapes » bascule sur **Anthropic** — c'est ce que fait le pipeline pour la
rédaction (`../backend/src/services/structuring.ts`), et le champ de clé
correspondant apparaît alors.

Les modèles par défaut sont ceux de `backend/src/env.ts` — `gpt-4o` et
`claude-opus-5` — pour que l'atelier n'invente pas un troisième jeu de
réglages à côté du pipeline et du script. Le champ « Modèle de découpage »
prend le pas dessus.

Le modèle **ne réécrit rien** : il découpe, titre et date. Le texte du
voyageur est repris au mot près, comme dans le reste de la chaîne.

## Réglages

| Réglage | Effet |
|---|---|
| Clé API OpenAI | Transcription, et découpage si le fournisseur est OpenAI |
| Modèle de transcription | `gpt-4o-transcribe` par défaut, `gpt-4o-mini-transcribe` pour moitié prix, `whisper-1` pour des horodatages |
| Langue forcée | `fr` par défaut. **À garder** : sur un vocal court truffé de noms étrangers, la détection automatique bascule régulièrement en anglais |
| Vocabulaire soufflé | Prénoms, noms de lieux, mots locaux — passé au `--prompt` du script |
| Modèle de découpage | `gpt-4o` par défaut ; suit le fournisseur quand on en change |
| Dossier sur le disque | Transcrit un dossier existant sans rien déposer dans le navigateur |
| Refaire les vocaux déjà transcrits | Le `--force` du script : ignore le cache |

Tout est retenu dans le `localStorage` du navigateur, y compris l'état ouvert
ou replié de chaque boîte. Les clés aussi, tant que la case « Retenir » est
cochée — c'est un outil de poste de travail, pas un service exposé.

## Marque

Le logo et les typographies vivent dans `public/` : `logo-memobook.svg`,
`fonts/Sora-Variable.ttf` (titres) et `fonts/GeneralSans-Variable.ttf` (texte
courant, avec son italique). Ils sont servis par le serveur local — **aucune
requête ne part chez Google Fonts**, et l'atelier fonctionne hors ligne une
fois la page chargée.

## Générer le carnet, et pourquoi c'est Beta

Le bouton « Générer le carnet » traduit l'état de l'atelier vers le contrat du
template — celui décrit par `MemoBook Generator/templates/travel-journal/data.json` — et l'envoie à
APITemplate. Il faut pour cela une **clé APITemplate** dans les réglages ;
l'identifiant du template est prérempli avec celui du dépôt.

La mise en page de chaque étape suit
[`LAYOUT_KB.md`](templates/travel-journal/LAYOUT_KB.md) — § « Longueur des
textes » et § « La répartition sur une étape à plusieurs pages » :

1. **Le récit se découpe en pages.** Paragraphes de 379 signes au plus (taille
   S), coupés sur une fin de phrase, ou sur une virgule quand un vocal enchaîne
   sans point. La première page, qui porte le bandeau, tient 560 signes et
   2 paragraphes ; chaque page de suite, sans bandeau ni titre, 880 signes et
   4 paragraphes. La dernière page ne reste jamais sous 200 signes si la
   précédente peut lui en céder.
2. **Les photos vont d'abord sur les pages de récit**, jusqu'à trois chacune,
   à parts égales. Le gabarit suit leur nombre :

   | Photos sur la page | Gabarit |
   |---|---|
   | 0 | `layout_story_opener` (première étape) ou `layout_story_facts` |
   | 1 | `layout_hero_top` si le texte y tient (380 / 680 signes), sinon photo flottante sous le récit |
   | 2 | `layout_split_left` |
   | 3 | `layout_collage` |

3. **Le surplus va sur des planches** (`layout_photo_page`, 3 à 5 photos), une
   au plus après chaque page de récit : **jamais deux planches de suite**. Ce
   qui ne tient pas reste hors du carnet, et la console le signale
   (`[carnet] étape N : … photo(s) laissée(s) hors du carnet`).

4. **Chaque photo va à l'emplacement qui la rogne le moins**, et n'est jamais
   rognée de plus d'un tiers : au-delà, elle est réduite, entière. La case
   « Photo de groupe, ne pas rogner », sous chaque photo, la fait toujours
   réduire plutôt que rogner (LAYOUT_KB § « Rognage des photos »).

Le bandeau ne porte pas d'étiquette (`tag`) : l'atelier n'avait que le lieu à y
mettre, déjà écrit dans le bandeau.

5. **Les photos suivent le récit.** Avant la mise en page, une analyse d'étape
   (même fournisseur et même modèle que le découpage) regarde les photos : le
   passage que chacune illustre, celles prises au même endroit, le nombre de
   visages. Chaque photo va sur la page de son passage, les photos d'une même
   scène restent ensemble, et le surplus fait une planche juste après la page
   dont il vient. Sans clé, les photos suivent l'ordre du voyage.
6. **Chaque nouveau lieu ouvre un chapitre** sur une carte
   (`layout_chapter_map`), quand l'analyse a situé le lieu. La carte se cadre
   sur la zone que les récits parcourent (les îles visitées, pas tout le
   pays), avec les contours détaillés de `assets/maps/detail/`.
7. **Deux pages en vis-à-vis n'ont jamais la même composition**, quand une
   alternative existe.
8. **Des fun facts tirés du récit**, si la case « Insérer des Fun facts » de
   la fiche du carnet est cochée (par défaut, comme dans l'app). La même
   analyse propose un encart par étape, noté sur 10. Seuls les mieux notés
   s'impriment, un toutes les trois pages au plus, sur une page où ils ne
   coûtent aucune ligne de récit.

La case **« Version imprimeur »**, dans les réglages, produit l'intérieur du
livre relié : sans couverture ni quatrième (imprimées sur la couverture
rigide), avec un nombre de pages pair. Le nombre de pages intérieures s'affiche
après le rendu : c'est celui à donner à l'outil de couverture Pumbo.

**Ces règles sont recopiées en code** dans `public/mise-en-page.js` (testé par
`backend/test/miseEnPageAtelier.test.ts`). L'atelier ne lit
pas `LAYOUT_KB.md` — c'est l'Agent Mise en page de l'app qui le lit. Une règle
ajoutée au KB doit donc aussi être portée ici pour changer les PDF de l'atelier.

**Quelle version tourne ?** L'en-tête affiche le commit publié (« version
abc1234 »). Chaque publication change l'adresse des scripts, si bien que le
navigateur ne peut plus resservir un ancien `app.js` ; si la version affichée
n'est pas celle du dernier commit de `main`, recharger la page suffit.

Le bouton **« Voir les layouts »** ouvre l'inspecteur de mise en page : chaque
layout du carnet, ses champs et ses limites.

## La couverture du livre relié

Le bouton **« Générer la couverture »** compose la couverture Pumbo — plat
verso, dos, plat recto — dans un nouvel onglet, au format exact de la fiche
technique, avec ses repères de coupe et de pli à l'écran. *Imprimer →
Enregistrer au format PDF* (marges *Aucune*, *Graphiques d'arrière-plan*
coché) donne le fichier à envoyer.

- **La fiche Pumbo** (le `.jsx` de leur outil de couverture) s'importe dans les
  réglages. Elle seule donne la largeur du dos, qui dépend du nombre de pages :
  une fiche par commande. Sans elle, l'atelier prend celle d'un relié de
  48 pages (dos de 8 mm) et le signale.
- **La photo de couverture** se désigne par l'étoile ☆ sous une photo ; sans
  étoile, l'atelier choisit la plus adaptée (portrait, bien résolue, pas une
  photo de groupe). C'est aussi celle de la couverture intérieure du carnet.

Règles et cotes : `LAYOUT_KB.md`, § « Couverture imprimée (Pumbo) ».

Trois raisons de l'appeler Beta, et de ne pas s'y fier pour un tirage :

1. **La conversion est mécanique.** Elle habille le texte du voyageur, elle ne
   l'écrit pas : pas de météo (elle ne s'imprime que si le vocal la dit, et
   l'atelier ne la cherche pas dans le récit), pas de stickers. Seule exception,
   les encarts « fun fact » : l'analyse d'étape en propose un par étape, tiré
   du récit, et la mise en page n'en garde qu'un toutes les trois pages au plus
   (case « Insérer des Fun facts » de la fiche du carnet ; LAYOUT_KB § « Les
   fun facts — dosage et matière »). Le pipeline du back-end fait le reste bien
   mieux.
2. **Les photos partent en base64** dans la requête. Au-delà de quelques
   dizaines, APITemplate refusera la charge ; l'outil s'arrête au-dessus de
   20 Mo plutôt que d'attendre une erreur illisible.
3. **Rien n'est validé** contre `payloadValidator.ts`. Un champ manquant se
   verra sur le PDF, pas avant.

C'est fait pour voir tout de suite à quoi le carnet ressemble. Pour un vrai
rendu, le chemin reste le pipeline.

## Limites connues

- La page ne survit pas à un rechargement : l'état vit en mémoire. Sauvegarde
  l'avancement (l'icône de l'en-tête) avant de fermer.
- Deux vocaux **différents** portant le même nom et la même taille sont
  considérés comme le même fichier. En pratique WhatsApp numérote les doublons,
  donc le cas ne se présente pas.
- Un vocal de plus de 25 Mo est refusé par l'API. Le script le signale et
  passe au suivant ; pour le découper :
  `ffmpeg -i long.oga -f segment -segment_time 1800 -c copy partie-%02d.oga`.
- Les photos sont portées en base64 dans l'état de la page : au-delà de
  quelques dizaines, le navigateur devient lourd. Décoche « Inclure les images
  en base64 » pour un JSON léger.

## Voir aussi

- [`TRANSCRIPTION.md`](TRANSCRIPTION.md) —
  le script en ligne de commande, ses options, son coût, et l'alternative
  gratuite en local (`whisper-cpp`)
- [`templates/travel-journal/LAYOUT_KB.md`](templates/travel-journal/LAYOUT_KB.md) —
  ce que la mise en page attend du carnet
