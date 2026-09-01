#!/usr/bin/env bash
#
# Transcription en lot des vocaux WhatsApp, via l'API OpenAI.
#
#   "./MemoBook Generator/transcribe-whatsapp.sh" ~/Downloads/vocaux
#   "./MemoBook Generator/transcribe-whatsapp.sh" "~/Downloads/Voice message.ogg.oga"
#
# Dépose les .ogg.oga dans un dossier, lance la commande : chaque vocal devient
# un .txt, et l'ensemble est recollé dans un seul fichier prêt à passer à
# l'étape de découpage en étapes du carnet. Un seul fichier en argument ne
# transcrit que celui-là.
#
# Seule dépendance : curl. Rien à installer, rien à builder.
#
set -euo pipefail

readonly API_URL="${OPENAI_API_BASE:-https://api.openai.com/v1}/audio/transcriptions"
# Limite de l'API. Un vocal WhatsApp d'une heure pèse ~30 Mo : au delà, il faut
# découper le fichier (voir docs/transcription-whatsapp.md).
readonly MAX_BYTES=26214400

usage() {
  cat <<'USAGE'
Usage : transcribe-whatsapp.sh [DOSSIER|FICHIER] [options]

  DOSSIER              dossier contenant les audios (défaut : le dossier courant)
  FICHIER              un seul audio : lui seul est transcrit

Options :
  -o, --out FICHIER    fichier de sortie groupé (défaut : DOSSIER/transcription.txt)
  -m, --model MODÈLE   modèle OpenAI (défaut : gpt-4o-transcribe)
  -l, --language CODE  langue forcée (défaut : fr)
  -p, --prompt TEXTE   vocabulaire à souffler au modèle : noms de lieux, prénoms
      --sort time|name ordre des fichiers (défaut : time, la date de fichier)
      --force          retranscrit même les fichiers déjà transcrits
      --dry-run        liste ce qui serait envoyé, sans appeler l'API
  -h, --help           cette aide

Clé d'API : $OPENAI_API_KEY, sinon lue dans ./.env ou ./backend/.env.
Point d'entrée : $OPENAI_API_BASE (défaut https://api.openai.com/v1).
USAGE
}

# --- Options ---------------------------------------------------------------

dir=""
out=""
model="gpt-4o-transcribe"
language="fr"
prompt=""
sort_by="time"
force=0
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)      out="${2:?--out attend un chemin}"; shift 2 ;;
    -m|--model)    model="${2:?--model attend un nom}"; shift 2 ;;
    -l|--language) language="${2:?--language attend un code}"; shift 2 ;;
    -p|--prompt)   prompt="${2:?--prompt attend un texte}"; shift 2 ;;
    --sort)        sort_by="${2:?--sort attend time ou name}"; shift 2 ;;
    --force)       force=1; shift ;;
    --dry-run)     dry_run=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            echo "Option inconnue : $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$dir" ] || { echo "Un seul dossier à la fois (déjà : $dir)" >&2; exit 2; }
      dir="$1"; shift ;;
  esac
done

dir="${dir:-.}"
single_file=""
if [ -f "$dir" ]; then
  single_file="$dir"
  dir=$(dirname "$dir")
elif [ ! -d "$dir" ]; then
  echo "Ni dossier ni fichier : $dir" >&2
  exit 1
fi
dir="${dir%/}"

case "$sort_by" in
  time|name) ;;
  *) echo "--sort attend « time » ou « name », pas « $sort_by »." >&2; exit 2 ;;
esac

if [ -n "$single_file" ]; then
  out="${out:-$dir/$(basename "$single_file").txt}"
else
  out="${out:-$dir/transcription.txt}"
fi
readonly parts_dir="$dir/transcriptions"

# --- Clé d'API -------------------------------------------------------------

read_env_key() {
  # Lit OPENAI_API_KEY dans un .env sans le sourcer : un `rm -rf` glissé dans
  # un fichier de config ne doit pas s'exécuter parce qu'on cherchait une clé.
  local file="$1"
  [ -f "$file" ] || return 1
  local line
  line=$(grep -m1 -E '^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY[[:space:]]*=' "$file" || true)
  [ -n "$line" ] || return 1
  line="${line#*=}"
  line="${line%\"}"; line="${line#\"}"
  line="${line%\'}"; line="${line#\'}"
  printf '%s' "$(printf '%s' "$line" | tr -d '[:space:]')"
}

if [ -z "${OPENAI_API_KEY:-}" ]; then
  for candidate in ".env" "backend/.env" "$dir/.env"; do
    OPENAI_API_KEY=$(read_env_key "$candidate" || true)
    if [ -n "${OPENAI_API_KEY:-}" ]; then
      echo "Clé lue dans $candidate"
      break
    fi
  done
fi

if [ -z "${OPENAI_API_KEY:-}" ] && [ "$dry_run" -eq 0 ]; then
  echo "OPENAI_API_KEY absent. export OPENAI_API_KEY=sk-… , ou pose-le dans ./.env" >&2
  exit 1
fi

command -v curl >/dev/null || { echo "curl est requis." >&2; exit 1; }

# --- Inventaire ------------------------------------------------------------

# WhatsApp nomme tous ses vocaux « Voice message.ogg.oga », « Voice message
# (1).ogg.oga »… Le tri alphabétique placerait donc (10) avant (2) : le tri par
# date de fichier suit l'ordre réel des téléchargements, et c'est le défaut.
file_mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then stat -f %m "$1"; else stat -c %Y "$1"; fi
}

file_size() {
  if stat -f %z "$1" >/dev/null 2>&1; then stat -f %z "$1"; else stat -c %s "$1"; fi
}

human_date() {
  if date -r "$1" '+%Y-%m-%d %H:%M' >/dev/null 2>&1; then
    date -r "$1" '+%Y-%m-%d %H:%M'
  else
    date -d "@$1" '+%Y-%m-%d %H:%M'
  fi
}

index_file=$(mktemp)
trap 'rm -f "$index_file"' EXIT

while IFS= read -r -d '' path; do
  case "$path" in
    *$'\n'*)
      echo "Ignoré (retour à la ligne dans le nom) : $path" >&2
      continue ;;
  esac
  printf '%s\t%s\n' "$(file_mtime "$path")" "$path" >> "$index_file"
done < <(if [ -n "$single_file" ]; then
  printf '%s\0' "$single_file"
else
  find "$dir" -maxdepth 1 -type f \
  \( -iname '*.oga' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.m4a' \
     -o -iname '*.mp3' -o -iname '*.mp4' -o -iname '*.mpga' -o -iname '*.mpeg' \
     -o -iname '*.wav' -o -iname '*.webm' -o -iname '*.flac' \) -print0
fi)

if [ ! -s "$index_file" ]; then
  echo "Aucun fichier audio à transcrire dans $dir" >&2
  exit 1
fi

sorted=$(mktemp)
trap 'rm -f "$index_file" "$sorted"' EXIT
if [ "$sort_by" = "time" ]; then
  sort -n -k1,1 "$index_file" > "$sorted"
else
  sort -t$'\t' -k2,2 "$index_file" > "$sorted"
fi

total=$(wc -l < "$sorted" | tr -d ' ')
if [ -n "$single_file" ]; then
  echo "1 fichier — modèle $model, langue $language"
else
  echo "$total fichier(s) audio dans $dir — modèle $model, langue $language, tri par $sort_by"
fi

# --- Transcription ---------------------------------------------------------

transcribe_one() {
  # Trois tentatives : les 429 (débit) et les 5xx passent presque toujours au
  # deuxième essai, et une transcription à moitié perdue coûte une relance
  # complète du lot.
  local path="$1" target="$2"
  local attempt=1 delay=2 body code

  while [ "$attempt" -le 3 ]; do
    body=$(mktemp)

    local curl_args
    curl_args=(-sS -o "$body" -w '%{http_code}' --max-time 900
      -X POST "$API_URL"
      -H "Authorization: Bearer $OPENAI_API_KEY"
      -F "file=@\"$path\""
      -F "model=$model"
      -F "language=$language"
      -F "response_format=text")
    # Un prompt de plusieurs mots doit rester UN argument.
    if [ -n "$prompt" ]; then
      curl_args=("${curl_args[@]}" -F "prompt=$prompt")
    fi

    set +e
    code=$(curl "${curl_args[@]}")
    local curl_status=$?
    set -e

    if [ "$curl_status" -eq 0 ] && [ "$code" = "200" ]; then
      # `response_format=text` renvoie la transcription nue, pas du JSON.
      mv "$body" "$target"
      return 0
    fi

    case "$code" in
      429|5*|000)
        echo "    HTTP $code — nouvelle tentative dans ${delay}s ($attempt/3)" >&2
        rm -f "$body"
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
        ;;
      *)
        echo "    Échec HTTP $code : $(head -c 400 "$body")" >&2
        rm -f "$body"
        return 1
        ;;
    esac
  done

  echo "    Abandon après 3 tentatives." >&2
  return 1
}

mkdir -p "$parts_dir"

n=0
failed=0
skipped=0

while IFS=$'\t' read -r mtime path; do
  n=$((n + 1))
  base=$(basename "$path")
  target="$parts_dir/$base.txt"
  size=$(file_size "$path")

  printf '[%02d/%s] %s (%s ko, %s)\n' "$n" "$total" "$base" \
    "$((size / 1024))" "$(human_date "$mtime")"

  if [ "$size" -gt "$MAX_BYTES" ]; then
    echo "    Ignoré : $((size / 1024 / 1024)) Mo dépasse la limite de 25 Mo de l'API." >&2
    failed=$((failed + 1))
    continue
  fi

  if [ -s "$target" ] && [ "$force" -eq 0 ]; then
    echo "    Déjà transcrit, ignoré (--force pour refaire)."
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "    (dry-run) serait envoyé à $model"
    continue
  fi

  if transcribe_one "$path" "$target"; then
    echo "    → $(wc -c < "$target" | tr -d ' ') caractères"
  else
    failed=$((failed + 1))
  fi
done < "$sorted"

if [ "$dry_run" -eq 1 ]; then
  echo "Dry-run terminé : rien n'a été envoyé."
  exit 0
fi

# --- Fichier groupé --------------------------------------------------------

# Un seul fichier demandé : le texte nu, sans cérémonie de lot.
if [ -n "$single_file" ]; then
  part="$parts_dir/$(basename "$single_file").txt"
  if [ -s "$part" ]; then
    cp "$part" "$out"
    echo
    echo "Transcription : $out"
    echo
    cat "$out"
    exit 0
  fi
  echo "Rien à écrire : la transcription a échoué." >&2
  exit 1
fi

# Reconstruit toujours depuis les .txt : le résultat est le même qu'on ait
# transcrit tout le lot ou repris une seule pièce manquante.
{
  printf '# Transcriptions — %s\n' "$dir"
  printf '# %s fichier(s), modèle %s, langue %s, tri par %s\n' \
    "$total" "$model" "$language" "$sort_by"
  printf '# Généré le %s\n' "$(date '+%Y-%m-%d %H:%M')"
  printf '#\n'
  printf "# Les dates sont celles des fichiers (téléchargement WhatsApp),\n"
  printf "# pas forcément celles de l'enregistrement.\n"

  i=0
  while IFS=$'\t' read -r mtime path; do
    i=$((i + 1))
    base=$(basename "$path")
    part="$parts_dir/$base.txt"
    printf '\n\n## %02d — %s\n' "$i" "$base"
    printf 'date-fichier: %s\n\n' "$(human_date "$mtime")"
    if [ -s "$part" ]; then
      cat "$part"
    else
      printf '(transcription manquante)\n'
    fi
  done < "$sorted"
  printf '\n'
} > "$out"

echo
echo "Fichier groupé : $out"
echo "Pièces détachées : $parts_dir/"
if [ "$skipped" -gt 0 ]; then
  echo "$skipped fichier(s) déjà transcrits, non renvoyés."
fi
if [ "$failed" -gt 0 ]; then
  echo "$failed fichier(s) en échec — relance la commande, les réussites ne seront pas refacturées." >&2
  exit 1
fi
