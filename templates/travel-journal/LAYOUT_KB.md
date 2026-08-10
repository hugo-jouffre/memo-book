# Mémo – Référentiel GPT pour le carnet de voyage MemoBook

Ce document sert de base de connaissance pour l'agent GPT qui génère le payload APITemplate du carnet **travel-journal**.

## Structure générale du payload
- **book_title, book_subtitle, authors, date_range, cover_photo** : requis pour la couverture.
- **days[]** : une entrée par journée/section. Les layouts sont exclusifs (activer 1 à 2 maximum par jour en fonction du besoin).
- **back_cover** : texte de clôture + image pleine page.
- Champs transverses utiles :
  - `day_intro` : `{ day_number, location, date, weather_icon, weather_summary, temperature, mood }`
  - `photos` : URLs optimisées (préférer CDN Webflow). `photo_captions` optionnel pour légender.
  - `fun_facts` : liste de faits courts.
  - `highlights` : 3–5 bullets max.
  - `sticker_groups` : tampons/emoji positionnés (top-left/right, bottom-left/right, center). `sticker_line` : rangée simple pour le layout moderne.

## Catalogue des layouts et quand les choisir
- **layout_storyboard** (collage éditorial) : jour/date/météo + note manuscrite + 1 à 3 photos inclinées + mini cartes. Idéal pour un résumé riche mais concis.
- **layout_hero_top** : grande photo héro en haut, texte dessous. Pour 1 photo iconique + récit principal.
- **layout_split_left** : texte à gauche, mosaïque à droite (2–4 photos). Quand on veut équilibrer récit détaillé et visuels variés.
- **layout_story_facts** : récit + encart fun facts. Utiliser si 2–4 faits courts ajoutent de la valeur pédagogique.
- **layout_collage** : mode scrapbook libre (texte + photos inclinées + facts). Bien pour une journée dense visuellement.
- **layout_story_opener** : page d'ouverture pleine largeur (kicker + `opener_body_html` + `opener_photos`). Parfait pour introduire une étape ou un changement de région.
- **layout_modern_journal** (inspiré Figma Make) : badge "Jour", chips lieu/date, météo, texte encadré avec scotch, 1–4 polaroids + rangée de stickers. À privilégier si 1 fun fact court et 2–4 photos fortes.
- **layout_postcard** : photo de fond, timbre météo, message manuscrit, mini checklist. Idéal pour une journée courte ou un moment carte postale.
- **layout_bento** : grille 2xN mêlant récit, fun facts, moments forts et 2–3 photos. Pour les journées multi-activités.
- **layout_timeline** : frise verticale (3–6 `timeline_events` ou fallback sur `highlights`) + 1–3 photos. Choisir lorsque la journée suit une chronologie nette.
- **layout_gallery_stack** : pile de polaroids avec légendes + petit bloc texte. Pour les journées centrées sur les images (3 photos ou plus).

### Champs spécifiques par layout
- **storyboard** : `storyboard_cards[]` (icon, title, body), `storyboard_quote` optionnel.
- **opener** : `opener_body_html`, `opener_kicker`, `opener_photos[]` (1–3).
- **timeline** : `timeline_events[]` objets `{ time?, title?, description, icon? }` (3–6). Si vide, utiliser `highlights` comme texte.
- **gallery_stack / modern_journal** : `photo_captions[]` alignées sur l'ordre des photos.
- **modern_journal** : `sticker_line[]` (emojis ou mots courts).

## Règles d'images
- Toujours fournir des URLs valides (CDN Webflow recommandé). Les images sont sécurisées par un fallback automatique (SVG) en cas d'erreur, mais ce fallback sert uniquement de secours visuel : il faut quand même viser des URLs fonctionnelles.
- Prioriser 1200–1600 px de large pour les photos principales (hero, fond postcard). Les polaroids acceptent des images plus petites mais nettes.
- Éviter les doublons : pas plus de 4 photos dans `layout_modern_journal`, 3 dans `layout_timeline`, 6 dans `layout_gallery_stack`.

## Bonnes pratiques de génération
- **1 layout fort par jour** : activer celui qui raconte le mieux, laisser les autres à `false`/absents.
- **Texte HTML** : utiliser `<p>` pour chaque idée, `<ul>/<li>` pour listes courtes ; pas de titres H1/H2 dans les blocs jour.
- **Fun facts** : 1–3 phrases, pas de pavé. Un seul suffit pour les layouts modernes/postcard.
- **Highlights** : 3 bullets max pour les layouts qui les affichent (postcard, bento, storyboard, highlights section globale).
- **Timeline** : si la journée suit des heures ou séquences claires, préférer `layout_timeline` et remplir `timeline_events`.
- **Opener** : réserver aux grands basculements (nouvelle ville/région, début/fin de voyage).

## Sélection rapide du layout (heuristique)
- Beaucoup de photos, peu de texte → `layout_gallery_stack`.
- 1 photo iconique + texte moyen → `layout_hero_top` ou `layout_postcard` si vibe carte postale.
- 2–4 photos + 1 fun fact + envie de badge jour/météo → `layout_modern_journal`.
- Journée en étapes horaires → `layout_timeline`.
- Mélange récit + facts + listes → `layout_bento`.
- Intro d'étape → `layout_story_opener`.

## Contraintes de longueur (éviter le débordement)
Respecter ces maximums **par paragraphe** pour garantir que le texte ne dépasse jamais de la page :
- `intro_text` : **700 caractères max** par paragraphe (2–3 paragraphes max).
- `body_html` (layout jour) : **420 caractères max** par paragraphe (2–3 paragraphes max).
- `fun_facts[]` : **140 caractères max** par paragraphe.
- `highlights[]` : **80 caractères max** par bullet.

## Exemple minimal par layout
```json
{
  "layout_modern_journal": true,
  "day_intro": {"day_number": "05", "location": "Kyoto", "date": "12 avr", "weather_icon": "⛅", "weather_summary": "Douceur"},
  "body_html": "<p>Récit…</p>",
  "photos": ["https://cdn.../photo1.jpg", "https://cdn.../photo2.jpg"],
  "photo_captions": ["Temple au matin", "Matcha break"],
  "fun_facts": ["Fun fact court"],
  "sticker_line": ["🍵", "⛩️"]
}
```
Adapte l'exemple selon le layout choisi en remplissant les champs spécifiques ci-dessus.
