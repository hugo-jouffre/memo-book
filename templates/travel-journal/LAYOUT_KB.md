# Contrat de mise en page — carnet `travel-journal`

Base de connaissance de l'agent qui produit le JSON envoyé au moteur PDF.

> **Règle de survie du dépôt.** Ce fichier décrit ce que `index.html` sait
> réellement afficher. Toute modification du template doit modifier ce fichier
> **dans le même commit**. C'est exactement ce qui avait dérivé : le KB
> documentait onze layouts dont un seul existait, et l'agent produisait des
> champs que personne ne lisait.

## Format

- Page **A5 : 420 × 595 pt** (1 unité Figma = 1 pt), sans fond perdu.
  Géométrie dans `print.json`, maquette Figma `geIpjYxG3WCkGrgJFpkuVC`.
- Marge de contenu : 30 pt. Les décors (tracé pointillé, stickers) débordent
  volontairement.
- Une page de carnet = un élément `.page`. Une entrée de `days[]` = une page.

## Structure du payload

| Champ | Type | Rôle |
|---|---|---|
| `book_title` | requis | Titre de couverture, sur la photo |
| `book_subtitle` | optionnel | Bandeau blanc incliné sous le titre |
| `authors`, `date_range` | optionnels | Signature en bas de couverture |
| `cover_photo` | optionnel | Photo pleine page de couverture |
| `render_profile` | `print` \| `preview` | **Fond du PDF, voir plus bas** |
| `brand_name`, `year` | optionnels | Colophon (défauts `MemoBook` / `2026`) |
| `intro_title`, `intro_text` | optionnels | Page d'introduction (`intro_text` en HTML) |
| `intro_photos[]` | 0 à 2 | Photos scotchées en haut de l'introduction |
| `days[]` | requis | Une page par entrée |
| `back_cover` | optionnel | Quatrième de couverture |

Pages toujours produites, dans l'ordre : **couverture → colophon →
introduction (si `intro_text`) → journées → quatrième de couverture**.

## Les deux profils de sortie

`render_profile` décide du fond. Une seule template, deux rendus :

- **`print`** — fond blanc. Destiné à l'imprimeur, dont le papier est **déjà
  crème** : réimprimer le crème donnerait un carnet jauni.
- **`preview`** — fond crème granulé, réplique du rendu final. C'est celui de
  l'aperçu partageable dans l'app, en attendant la version imprimée.

Défaut : `preview`. Côté back-end, la variable `RENDER_PROFILE` fait foi.

## Champs d'une journée

| Champ | Type | Notes |
|---|---|---|
| `title` | requis | Titre manuscrit en tête du récit |
| `body_html` | requis | Récit. `<p>` par idée, `<ul>/<li>` pour les listes. Pas de `<h1>`/`<h2>` |
| `day_intro` | optionnel | Affiche le bandeau : `{ day_number, location, date, weather_key }` |
| `weather_key` | `sun` \| `sun-wind` \| `cloud` \| `rain` \| `snow` | Icône mise en avant ; les quatre autres restent estompées |
| `tag` | optionnel | Étiquette manuscrite (« Top départ »). **Trois mots max**, sinon elle déborde |
| `fun_facts[]` | optionnel | **Seul le premier est affiché** |
| `fun_facts_title` | optionnel | Titre de la carte. Défaut « Fun fact » ; aussi « Infos », « Culture générale » |
| `photos[]` | optionnel | Nombre utilisé selon le layout, voir ci-dessous |

`highlights`, `sticker_groups`, `timeline_events`, `storyboard_cards`,
`global_stats` restent acceptés par le schéma mais **ne sont pas rendus** :
ne pas les produire tant qu'un layout ne les consomme pas.

## Catalogue des layouts

Un seul drapeau à `true` par journée. En cas de conflit, l'ordre ci-dessous
tranche : le premier actif l'emporte.

| Drapeau | Rendu | Quand le choisir | Photos |
|---|---|---|---|
| `layout_hero_top` | Grande photo en tête, récit dessous | Une photo iconique porte la journée | 1 |
| `layout_split_left` | Carte info à gauche, récit en colonne à droite, puis deux photos en bas | Un fait à mettre en avant et deux belles images | 2 |
| `layout_collage` | Récit pleine largeur puis 2 ou 3 photos inclinées en bas | Journée dense visuellement | 2–3 |
| *(par défaut)* | Récit, puis carte info et photo flottantes en bas de page | Ouverture de journée, cas le plus courant | 0–1 |

Le cas par défaut couvre aussi `layout_story_opener` et `layout_story_facts` :
le validateur exige au moins un drapeau, n'importe lequel de ces deux convient.

## Contraintes de longueur

Appliquées par `backend/src/services/payloadValidator.ts` — un dépassement est
une **erreur**, pas un avertissement :

| Champ | Maximum |
|---|---|
| `intro_text` | 700 caractères par paragraphe, 3 paragraphes |
| `body_html` | 420 caractères par paragraphe, 2–3 paragraphes |
| `fun_facts[]` | 140 caractères |
| `highlights[]` | 80 caractères |

## Réglure et rythme vertical

La réglure du papier est générée, pas dessinée : elle se répète tous les
`--mb-line`. Elle n'est juste que si **tout ce qu'elle traverse occupe un
multiple entier de cette valeur** — le titre pèse exactement deux interlignes,
la marge d'un paragraphe exactement un. Un bloc d'une autre hauteur décale
toutes les lignes suivantes, et l'écart texte/ligne dérive le long de la page.

Chaque paragraphe est suivi d'**une ligne vide** : elle montre l'emplacement
resté libre dans le gabarit, comme sur un carnet où l'on n'a pas rempli la page.

## Règles d'images

- URLs absolues et publiques (CDN Webflow). Pas de chemin relatif : le moteur
  PDF ne reçoit que du HTML et du CSS, sans aucun fichier joint.
- 1200–1600 px de large pour les photos de couverture et les photos héros.
- Les photos sont recadrées en `object-fit: cover` et pivotées de quelques
  degrés : ne pas envoyer une image dont un visage touche déjà le bord.

## Pièges à connaître

- **Jamais `null`.** Jinja2 imprime la chaîne littérale « None » dans le
  carnet. Omettre la clé plutôt que de l'envoyer vide.
- **Tableaux vides.** `[]` et l'absence du champ donnent le même rendu ; c'est
  volontaire, mais ça veut dire qu'une carte info vide n'apparaît pas du tout.
- **`body_html` est injecté tel quel** (`| safe`). Aucun script, aucun style
  en ligne, aucune balise autre que `<p>`, `<br>`, `<b>`, `<i>`, `<ul>`, `<li>`.

## Exemple minimal

```json
{
  "render_profile": "preview",
  "book_title": "Philippines",
  "authors": "Maÿlis, Claire et Augustin",
  "date_range": "février 2026",
  "cover_photo": "https://cdn.../cover.jpg",
  "intro_text": "<p>Il y a des voyages qu'on prépare pendant des mois…</p>",
  "days": [
    {
      "title": "36 heures plus tard, me voilà aux Philippines",
      "day_intro": {
        "day_number": "01",
        "location": "De Barcelone à Cebu",
        "date": "22-23 fev 2026",
        "weather_key": "sun"
      },
      "tag": "Top départ",
      "layout_story_opener": true,
      "body_html": "<p>Départ de Barcelone, sac sur le dos…</p>",
      "fun_facts": ["Les Philippines comptent plus de 7000 îles. Oui oui."],
      "photos": ["https://cdn.../jour01.jpg"]
    }
  ]
}
```

## Vérifier son rendu

```bash
cd backend
npm run template:lint                      # dialecte Jinja + invariants CSS
npm run render:local -- --offline --png    # PDF + un PNG par page
npm run render:local -- --data mon.json --validate --png
```
