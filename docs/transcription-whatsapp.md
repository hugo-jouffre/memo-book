# Transcrire les vocaux WhatsApp

Comment passer d'un dossier de `Voice message.ogg.oga` à un fichier texte
exploitable pour la suite de la chaîne (découpage en étapes, association des
photos, payload du carnet).

```bash
export OPENAI_API_KEY=sk-…
./scripts/transcribe-whatsapp.sh ~/Downloads/vocaux
```

Un **seul** vocal, sans toucher au reste du dossier :

```bash
./scripts/transcribe-whatsapp.sh ~/Downloads/"Voice message.ogg.oga"
```

C'est la forme à préférer pour un essai. Viser un dossier fourre-tout comme
`~/Downloads` transcrirait **tous** ses audios et vidéos — le `.mp4` des
vacances compris. En cas de doute, `--dry-run` liste ce qui partirait sans rien
envoyer.

Sur un fichier unique, le script écrit la transcription nue à côté du vocal.
Sur un dossier, il écrit deux choses :

- `~/Downloads/vocaux/transcriptions/<nom du vocal>.txt` — une pièce par vocal ;
- `~/Downloads/vocaux/transcription.txt` — tout recollé dans l'ordre, avec un
  en-tête par vocal.

Seule dépendance : `curl`. Rien à installer, rien à builder.

## Le bon point d'entrée de l'API

L'extrait fourni par le tableau de bord OpenAI
(`POST /v1/realtime/client_secrets`, `gpt-realtime-whisper`, `server_vad`,
`turn_detection`) est celui de l'**API temps réel** : il ouvre une session
WebSocket où l'audio arrive en flux PCM 24 kHz, pour dialoguer avec un modèle
vocal. Ce n'est pas ce qu'il faut ici : il faudrait décoder l'Opus des fichiers
WhatsApp en PCM, gérer une socket, et découper soi-même les tours de parole —
tout ça pour transcrire des fichiers déjà enregistrés.

Pour des fichiers, l'endpoint est **`POST /v1/audio/transcriptions`** : un
`multipart/form-data`, un fichier, une réponse texte.

```bash
curl https://api.openai.com/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F file=@"Voice message.ogg.oga" \
  -F model=gpt-4o-transcribe \
  -F language=fr \
  -F response_format=text
```

C'est exactement ce que le script fait, en boucle et avec un cache.

## Le format WhatsApp

Un vocal WhatsApp est de l'**Opus dans un conteneur Ogg**. Le double suffixe
`.ogg.oga` vient du téléchargement, pas du format. L'extension utile est la
dernière, `.oga`, et elle fait partie des formats acceptés par l'API (`flac`,
`m4a`, `mp3`, `mp4`, `mpeg`, `mpga`, `oga`, `ogg`, `wav`, `webm`) : **aucune
conversion `ffmpeg` n'est nécessaire**.

Limite de l'API : **25 Mo par fichier**, soit une heure environ de vocal
WhatsApp. Le script refuse les fichiers plus gros plutôt que de les envoyer
pour rien. Pour découper un enregistrement trop long :

```bash
ffmpeg -i long.oga -f segment -segment_time 1800 -c copy partie-%02d.oga
```

## Options

| Option | Effet |
|---|---|
| `-o, --out FICHIER` | Chemin du fichier groupé (défaut `DOSSIER/transcription.txt`) |
| `-m, --model MODÈLE` | Défaut `gpt-4o-transcribe`. `gpt-4o-mini-transcribe` pour le moins cher, `whisper-1` pour des sous-titres horodatés |
| `-l, --language CODE` | Défaut `fr`. **À garder** : sur un vocal court truffé de noms étrangers, la détection automatique bascule régulièrement en anglais |
| `-p, --prompt TEXTE` | Vocabulaire soufflé au modèle : prénoms, noms de lieux, mots locaux |
| `--sort time\|name` | Ordre des fichiers. Défaut `time` |
| `--force` | Retranscrit même ce qui l'a déjà été |
| `--dry-run` | Liste ce qui serait envoyé, sans appeler l'API |

**Le tri par défaut n'est pas alphabétique**, et c'est délibéré : WhatsApp
nomme tous les vocaux `Voice message.ogg.oga`, `Voice message (1).ogg.oga`… Un
tri alphabétique place `(10)` avant `(2)`. Le tri par date de fichier suit
l'ordre réel des téléchargements. Il reste à vérifier d'un coup d'œil : c'est
la date du **téléchargement**, pas celle de l'enregistrement, et elle ne
survit pas à une copie de dossier.

Le `--prompt` vaut le détour dès qu'un voyage a son vocabulaire propre :

```bash
./scripts/transcribe-whatsapp.sh ~/Downloads/vocaux \
  -p "Voyage aux Philippines : Cebu, Moalboal, Siquijor, Maÿlis, Augustin, jeepney, barangay"
```

## Reprises et coût

Chaque vocal transcrit est gardé dans `transcriptions/`. Relancer la commande
ne renvoie que ce qui manque : une coupure réseau au 18ᵉ vocal sur 20 ne coûte
pas les 17 premiers une deuxième fois. Les erreurs de débit (`429`) et les
erreurs serveur sont réessayées trois fois, avec un délai qui double.

Ordre de grandeur du coût : quelques dixièmes de centime par minute d'audio —
une heure de vocaux reste sous le prix d'un café. `gpt-4o-mini-transcribe`
coûte environ moitié moins que `gpt-4o-transcribe` et suffit largement pour un
essai. Le tarif exact est sur <https://openai.com/api/pricing/>, il n'est pas
recopié ici pour ne pas vieillir.

`OPENAI_API_BASE` remplace le point d'entrée (défaut
`https://api.openai.com/v1`), pour un proxy d'entreprise — ou pour rejouer le
script contre un faux serveur sans rien dépenser.

## L'alternative gratuite

Si le volume grossit ou si les vocaux sont sensibles, la transcription tourne
très bien **en local**, gratuitement et hors ligne :

```bash
# macOS
brew install whisper-cpp
whisper-cpp --model ggml-large-v3-turbo.bin --language fr --output-txt vocal.oga

# multiplateforme, GPU ou CPU
pipx install faster-whisper
```

Ce qu'on y gagne : aucun coût, aucune clé, rien qui sorte de la machine.
Ce qu'on y perd : quelques minutes de mise en place, le téléchargement du
modèle (1 à 3 Go), et un temps de traitement qui dépend de la machine. Sur du
français propre, l'écart de qualité avec `gpt-4o-transcribe` est faible ; sur
un vocal enregistré dans un jeepney, il se voit.

Recommandation : rester sur l'API tant que la boucle « je rentre, je dépose,
je relis » se compte en dizaines de vocaux. Basculer en local le jour où c'est
un flux quotidien.

## Rapport avec le back-end

Le pipeline MemoBook transcrit déjà les vocaux enregistrés dans l'app, par le
même endpoint et le même modèle
(`backend/src/services/transcription.ts`, variable `OPENAI_TRANSCRIPTION_MODEL`).
Ce script est la porte d'entrée **hors app** : il ne remplace pas le pipeline,
il alimente à la main la même étape, quand les souvenirs sont arrivés par
WhatsApp plutôt que par le micro de l'app.
