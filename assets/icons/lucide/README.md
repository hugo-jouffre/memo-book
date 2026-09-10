# Icônes Lucide — bouche-trous, pas de la marque

Onze icônes empruntées à [Lucide](https://lucide.dev) (licence ISC), parce que le
jeu de marque de `../brand-icons` ne couvre pas encore l'écran de chat.

| Fichier | Rôle dans l'app | Asset généré |
|---|---|---|
| `volume-2.svg` | Lire un message à voix haute | `IconLucideSpeaker` |
| `copy.svg` | Copier un message | `IconLucideCopy` |
| `camera.svg` | Prendre ou joindre une photo | `IconLucideCamera` |
| `keyboard.svg` | Passer à la saisie au clavier | `IconLucideKeyboard` |
| `calendar.svg` | La date d'une retranscription | `IconLucideCalendar` |
| `sparkles.svg` | Le signe « écrit par MEMO » | `IconLucideSparkles` |
| `play.svg` | Jouer un vocal | `IconLucidePlay` |
| `pause.svg` | Mettre un vocal en pause | `IconLucidePause` |
| `square.svg` | Arrêter l'enregistrement | `IconLucideStop` |
| `arrow-down.svg` | « Retourner en bas » | `IconLucideArrowDown` |
| `arrow-up.svg` | Envoyer le message écrit | `IconLucideArrowUp` |

## Pourquoi elles sont préfixées

Les assets s'appellent `IconLucide…` et non `Icon…` **exprès** : à la lecture
d'une vue, on voit tout de suite ce qui vient de la marque et ce qui est
provisoire. Le jour où Clara dessine le haut-parleur, on renomme l'asset en
`IconSpeaker`, on retire le SVG d'ici, et le compilateur signale les vues à
mettre à jour. Un nom neutre aurait rendu la dette invisible.

C'est un écart assumé à la règle R10 de `docs/ui-development.md` (« les assets
viennent de Figma, jamais d'ailleurs) — voir la fiche du chat, §14.

## Régénérer les assets

```bash
python3 ios/Tools/import-lucide-icons.py
```

Le script pose l'encre de la marque à la place de `currentColor`, retire les
`width`/`height` de la balise racine (le cadrage vient de la `viewBox`, la taille
de la vue), et remplit `play`, `pause` et `square` : un triangle de lecture creux
ne se lit pas comme « joue ça ».

## Mettre à jour depuis Lucide

```bash
for i in volume-2 copy camera keyboard calendar sparkles play pause arrow-down arrow-up square; do
  curl -sL "https://cdn.jsdelivr.net/npm/lucide-static@1.43.0/icons/$i.svg" -o "assets/icons/lucide/$i.svg"
done
```

La version est **épinglée** : Lucide redessine ses icônes d'une version à
l'autre, et un `@latest` ferait bouger l'app sans qu'aucun commit ne le dise.
