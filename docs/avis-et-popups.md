# Parler aux voyageurs sans livrer de version

> T273, Hugo, 05/11/2026 : « Vérifier qu'on peut envoyer des popups aux
> utilisateurs sans leur faire retélécharger l'app, et comprendre comment on le
> fait. Commencer à recueillir leur avis dans l'app, **sans** proposer de note
> sur l'App Store pour le moment. »

## 1. La réponse, en une ligne

**Oui**, et par quatre chemins — dont trois existaient déjà sans qu'on le sache.
Ce qui demandait une livraison, c'était la **modale** : elle est faite
(19/11/2026), et c'est la dernière qu'on livre pour ça.

## 2. Les quatre chemins

| Chemin | Ce qu'on peut dire | Ce qu'il faut pour l'envoyer |
|---|---|---|
| **La notification** | Un titre, un corps, une destination dans l'app | Du code serveur (`services/notificationCopy.ts`) et un déploiement. Pas de livraison d'app |
| **Une bulle de MEMO** | Un texte, dans le fil d'un voyage | Une écriture en base. Deux notifications le font déjà (`docs/notifications.md` § 1) |
| **Une vitrine** (`showcases`) | Une carte avec titre, sous-titre, image et lien, sur l'accueil et l'écran d'entrée | **Une insertion en base.** Déjà servie (`routes/home.ts`) |
| **La modale d'avis** (`feedback_campaigns`) | Un titre, un sous-titre, des questions, un bouton | **Une insertion en base** |

⚠️ **Ce qui demande toujours une livraison** : un **bouton** sous une bulle de
MEMO (le catalogue est fermé côté app — une app plus ancienne n'affiche rien,
`docs/conversation.md` § 6 bis), et toute **forme** de question que l'app ne
dessine pas encore (§ 4).

## 3. La modale d'avis

Les tables existaient depuis le 07/09/2026 — `feedback_campaigns`,
`feedback_questions`, `feedback_responses`, `feedback_answers` — et **rien ne
les servait**. Deux routes les branchent (T273) :

| Route | Quoi |
|---|---|
| `GET /v1/feedback-campaign` | La campagne à montrer à ce compte, ou `null`. **La lire compte comme un affichage** |
| `POST /v1/feedback-campaigns/:id/response` | Ce qu'on en a fait : répondu, ou fermé |

Trois règles décident de l'affichage, dans cet ordre : la campagne est
**ouverte** (drapeau levé, fenêtre en cours), elle a au moins une question, et
cette personne ne l'a pas vue plus de `maxDisplays` fois. Une campagne
**répondue ou fermée** ne revient jamais — répondre, c'est en avoir fini avec
elle. L'app ne la demande qu'**une fois par lancement**, sur l'accueil.

**`audience` se lit depuis le 23/11/2026** (`services/feedbackAudience.ts`).
Quatre critères, qui **se cumulent** — une campagne qui en porte deux ne paraît
qu'à ceux qui remplissent les deux :

| Critère | Ce qu'il vaut |
|---|---|
| `registeredForDays` | Le compte existe depuis au moins tant de jours |
| `hasOrdered` | Il a déjà commandé un carnet imprimé — un brouillon ne compte pas |
| `isSubscriber` | Il raconte sans limite, aujourd'hui |
| `minMemories` | Il a déjà raconté au moins tant de souvenirs — photos exclues |

```sql
UPDATE feedback_campaigns
SET audience = '{"registeredForDays": 7, "hasOrdered": true}'::jsonb
WHERE key = 'avis-v1';
```

Une audience **vide** (`{}`) ou absente s'adresse à tout le monde : c'est le
même sens, écrit autrement.

⚠️ **Un critère inconnu ferme la campagne**, comme avant qu'on lise la colonne :
une audience qu'on ne sait pas lire ne vaut pas une audience vide, et le
serveur le dit dans ses journaux (« audience illisible », avec la clé de la
campagne). C'est ce qui permet d'en inventer un en base sans risquer qu'il soit
ignoré en silence — mieux vaut une modale qui ne paraît pas qu'une modale
servie à côté de sa cible.

## 4. Les formes de question

| Forme | Ce qu'elle demande en `config` |
|---|---|
| `text` | Rien — `placeholder` suffit |
| `choice` | `{ "options": [{ "key": "…", "label": "…", "hint": "…" }] }` |
| `slider` | `{ "min": 0, "max": 4, "step": 1, "ticks": […], "minLabel": "…", "maxLabel": "…" }` |
| `rating` | `{ "max": 5 }` |

**Les quatre se dessinent** depuis le 23/11/2026. Le curseur est celui du
ratio photo/texte (`BrandSlider`) : même rail, même poignée, mêmes crans
écrits dessous, même réglage au balayage pour VoiceOver. La note est une
rangée d'étoiles de la marque, pleines jusqu'à la note, au trait ensuite.

Deux choses à savoir en écrivant une campagne :

- **Des crans courts.** Le cran du moment s'écrit en gras, donc plus large, et
  le curseur le tronque au-delà d'environ six caractères : « Souvent » devient
  « Souv… ». C'est une contrainte d'écriture, pas de dessin — le même curseur
  sert le ratio, dont les crans sont des pourcentages.
- **Une note part de 1.** Zéro étoile serait une absence de réponse, pas un
  avis ; `min` est donc ignoré pour un `rating`.

⚠️ **Rien ne part avec une valeur par défaut.** Le curseur se pose au milieu
pour qu'on voie l'échelle, mais **pâli** tant que le doigt n'a rien bougé, et
le modèle ne retient rien : une note de 3 sur 5 que personne n'a touchée serait
un avis inventé. Sur une question obligatoire, c'est aussi ce qui tient le
bouton d'envoi fermé.

⚠️ **Une campagne qu'on ne sait pas dessiner entière ne se montre pas du tout**
(`FeedbackQuestion.isDrawable`). Une modale à trous rendrait un avis qui ne
répond pas à ce qu'on a demandé — et la question sautée serait peut-être celle
qui comptait. Trois cas : une forme que cette version ne connaît pas, une liste
**sans option**, et une échelle impossible — bornes à l'envers, pas qui ne
tombe pas juste sur la borne haute, plus de onze crans, ou des étiquettes en
nombre différent des crans. Elle paraîtra d'elle-même quand l'app saura la
dessiner, sans qu'on touche à la base.

## 5. Poser une campagne

Une insertion, et rien d'autre. Dans la base de production
(`railway run --service worker`) :

```sql
WITH campagne AS (
  INSERT INTO feedback_campaigns (id, key, title, subtitle, "submitLabel", "isActive", "maxDisplays", "createdAt", "updatedAt")
  VALUES (gen_random_uuid(), 'avis-v1', 'Comment ça se passe ?', 'Deux questions, trente secondes.', 'Envoyer', true, 1, now(), now())
  RETURNING id
)
INSERT INTO feedback_questions (id, "campaignId", position, kind, prompt, placeholder, "isRequired", config, "createdAt", "updatedAt")
SELECT gen_random_uuid(), campagne.id, 1, 'choice', 'Tu racontes tes voyages…', NULL, true,
       '{"options":[{"key":"chaque-jour","label":"Chaque jour"},{"key":"au-retour","label":"Plutôt au retour"}]}'::jsonb,
       now(), now()
FROM campagne
UNION ALL
SELECT gen_random_uuid(), campagne.id, 2, 'text', 'Qu''est-ce qui te manque ?', 'Dis-nous tout.', false, NULL, now(), now()
FROM campagne;
```

Pour l'arrêter : `UPDATE feedback_campaigns SET "isActive" = false WHERE key = 'avis-v1';`
Les réponses restent, et une campagne rouverte ne repropose rien à ceux qui ont
déjà répondu.

Pour les lire :

```sql
SELECT q.prompt, a."choiceKey", a."textValue", r."appVersion", r."submittedAt"
FROM feedback_answers a
JOIN feedback_responses r ON r.id = a."responseId"
JOIN feedback_questions q ON q.id = a."questionId"
JOIN feedback_campaigns c ON c.id = r."campaignId"
WHERE c.key = 'avis-v1'
ORDER BY r."submittedAt" DESC;
```

Et pour savoir **combien l'ont écartée** — c'est un résultat aussi :

```sql
SELECT count(*) FILTER (WHERE "submittedAt" IS NOT NULL) AS repondu,
       count(*) FILTER (WHERE "dismissedAt" IS NOT NULL) AS ferme,
       count(*) AS montre
FROM feedback_responses r JOIN feedback_campaigns c ON c.id = r."campaignId"
WHERE c.key = 'avis-v1';
```

## 6. Ce qui existait déjà pour l'avis

**« Partager mes retours »** et « Écris à notre équipe » (T226) écrivent dans
`support_messages` — c'est l'avis **spontané**, celui qu'on vient donner. La
modale est l'avis **sollicité**, celui qu'on va chercher. Les deux se lisent à
des endroits différents et ne se remplacent pas.

## 7. Ce qui n'est toujours pas fait

- Un **bouton** sous une bulle de MEMO : le catalogue des puces est fermé côté
  app (§ 2), donc en poser une neuve demande encore une livraison.
- Une **note sur l'App Store** : écartée par Hugo pour le moment, et ce n'est
  pas un oubli — on demande un avis, pas une étoile.

Le curseur, les étoiles et le filtre d'audience sont faits le 23/11/2026.
