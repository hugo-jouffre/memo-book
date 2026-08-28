#!/usr/bin/env bash
#
# Crée la base PostgreSQL 16 managée de MemoBook chez Scaleway, région fr-par
# (Paris), et imprime le DATABASE_URL à poser dans les secrets de déploiement.
#
#   ./scripts/provision-db-scaleway.sh
#   ./scripts/provision-db-scaleway.sh --name memobook-staging --allow 203.0.113.7/32
#
# Le script est idempotent : relancé, il retrouve l'instance par son nom, ne
# recrée ni la base ni les règles d'ACL déjà en place, et se contente de
# rafraîchir le certificat TLS. C'est ce qui permet de le relire comme la
# description de l'infrastructure — et pas comme une commande jouée une fois
# dans un terminal que personne n'a gardé.
#
# Pourquoi Paris : les vocaux sont des données personnelles (RGPD). Les
# transcriptions, le texte rédigé et les métadonnées vivent dans cette base ;
# elles restent en France, sauvegardes comprises (--backup-same-region).
#
# Dépendances : scw (CLI Scaleway), jq, openssl, curl.
# Voir docs/database.md pour le mode d'emploi complet.
#
set -euo pipefail

# --- Valeurs par défaut ----------------------------------------------------

name="memobook-prod"
region="fr-par"
engine="PostgreSQL-16"
node_type="DB-DEV-S"
volume_type="sbs_5k"
volume_size="10GB"
ha=false
encryption=true
db_name="memobook"
db_user="memobook"
cert_dir="./secrets"
dry_run=0
allowed_ips=()

usage() {
  cat <<'USAGE'
Usage : provision-db-scaleway.sh [options]

Options :
  -n, --name NOM          nom de l'instance (défaut : memobook-prod)
  -d, --database NOM      base applicative (défaut : memobook)
  -u, --user NOM          utilisateur applicatif (défaut : memobook)
  -t, --node-type TYPE    type de nœud (défaut : DB-DEV-S)
      --engine MOTEUR     moteur (défaut : PostgreSQL-16)
      --region RÉGION     fr-par | nl-ams | pl-waw (défaut : fr-par, Paris)
      --volume-type TYPE  lssd | bssd | sbs_5k | sbs_15k (défaut : sbs_5k)
      --volume-size T     taille du volume (défaut : 10GB)
      --ha                haute disponibilité : un second nœud en veille
      --no-encryption     désactive le chiffrement au repos (activé par défaut)
  -a, --allow CIDR        IP autorisée sur l'endpoint public, répétable
                          (défaut : l'IP publique de cette machine)
      --cert-dir DOSSIER  où écrire le certificat de l'autorité (défaut : ./secrets)
      --dry-run           affiche les commandes sans rien créer
  -h, --help              cette aide

Authentification : `scw init` une fois, ou les variables SCW_ACCESS_KEY,
SCW_SECRET_KEY, SCW_DEFAULT_PROJECT_ID.

Le mot de passe n'est affiché qu'à la création de l'instance : Scaleway ne le
restitue jamais ensuite. Range-le tout de suite dans le gestionnaire de secrets
du déploiement.
USAGE
}

# --- Options ---------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--name)        name="${2:?--name attend un nom}"; shift 2 ;;
    -d|--database)    db_name="${2:?--database attend un nom}"; shift 2 ;;
    -u|--user)        db_user="${2:?--user attend un nom}"; shift 2 ;;
    -t|--node-type)   node_type="${2:?--node-type attend un type}"; shift 2 ;;
    --engine)         engine="${2:?--engine attend un moteur}"; shift 2 ;;
    --region)         region="${2:?--region attend une région}"; shift 2 ;;
    --volume-type)    volume_type="${2:?--volume-type attend un type}"; shift 2 ;;
    --volume-size)    volume_size="${2:?--volume-size attend une taille}"; shift 2 ;;
    --ha)             ha=true; shift ;;
    --no-encryption)  encryption=false; shift ;;
    -a|--allow)       allowed_ips+=("${2:?--allow attend un CIDR}"); shift 2 ;;
    --cert-dir)       cert_dir="${2:?--cert-dir attend un dossier}"; shift 2 ;;
    --dry-run)        dry_run=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- Prérequis -------------------------------------------------------------

for binary in scw jq openssl curl; do
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "Il manque « $binary ». Installe-le puis relance." >&2
    exit 1
  fi
done

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }

run() {
  if [ "$dry_run" -eq 1 ]; then
    printf '  [dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# --- L'instance ------------------------------------------------------------

say "Instance « $name » ($engine, $region)"

instance_id="$(
  scw rdb instance list name="$name" region="$region" -o json \
    | jq -r --arg n "$name" '[.. | objects | select(.name? == $n) | .id] | first // empty'
)"

password=""

if [ -n "$instance_id" ]; then
  note "déjà là : $instance_id"
  note "le mot de passe n'est pas récupérable ; pour le réinitialiser :"
  note "  scw rdb user update instance-id=$instance_id name=$db_user password=<nouveau> region=$region"
else
  # Contraintes Scaleway : 8 à 128 caractères, au moins un chiffre, une
  # majuscule, une minuscule et un caractère spécial. L'hexadécimal évite les
  # caractères qu'il faudrait percent-encoder dans le DATABASE_URL.
  if [ "$dry_run" -eq 1 ]; then
    password="MOT_DE_PASSE_GENERE"
  else
    password="$(openssl rand -hex 24)Aa1!"
  fi

  create_args=(
    name="$name"
    engine="$engine"
    node-type="$node_type"
    user-name="$db_user"
    password="$password"
    volume-type="$volume_type"
    volume-size="$volume_size"
    is-ha-cluster="$ha"
    # Les sauvegardes automatiques restent dans la région de l'instance :
    # les données personnelles ne quittent pas la France.
    backup-same-region=true
    encryption.enabled="$encryption"
    region="$region"
  )

  note "création…"
  if [ "$dry_run" -eq 1 ]; then
    run scw rdb instance create "${create_args[@]}"
    instance_id="ID_DE_L_INSTANCE"
  else
    instance_id="$(scw rdb instance create "${create_args[@]}" -o json | jq -r '.id')"
    note "créée : $instance_id"
    note "attente de l'état « ready » (quelques minutes)…"
    scw rdb instance wait "$instance_id" region="$region" >/dev/null
  fi
fi

# --- La base applicative ---------------------------------------------------

say "Base « $db_name »"

if [ "$dry_run" -eq 1 ]; then
  run scw rdb database create instance-id="$instance_id" name="$db_name" region="$region"
elif scw rdb database list instance-id="$instance_id" region="$region" -o json \
      | jq -e --arg n "$db_name" 'any(.[]; .name == $n)' >/dev/null; then
  note "déjà là"
else
  scw rdb database create instance-id="$instance_id" name="$db_name" region="$region" >/dev/null
  note "créée"
  # `all` = propriétaire de la base. Prisma y crée les tables des migrations et
  # pg-boss son propre schéma : un droit `readwrite` ne suffirait pas.
  scw rdb privilege set instance-id="$instance_id" database-name="$db_name" \
    user-name="$db_user" permission=all region="$region" >/dev/null
  note "droits « all » accordés à $db_user"
fi

# --- Les IP autorisées -----------------------------------------------------

say "Filtrage IP de l'endpoint public"

if [ "${#allowed_ips[@]}" -eq 0 ]; then
  detected="$(curl -sS --max-time 10 https://ipv4.icanhazip.com 2>/dev/null || true)"
  if [ -z "$detected" ]; then
    note "impossible de détecter l'IP publique de cette machine."
    note "relance avec --allow <CIDR> : sans règle d'ACL, personne ne peut se connecter."
  else
    allowed_ips=("${detected}/32")
    note "IP de cette machine détectée : ${allowed_ips[0]}"
    note "en production, ajoute l'IP de sortie des serveurs API et worker."
  fi
fi

existing_acl=""
if [ "$dry_run" -eq 0 ] && [ "${#allowed_ips[@]}" -gt 0 ]; then
  existing_acl="$(
    scw rdb acl list instance-id="$instance_id" region="$region" -o json \
      | jq -r '.. | objects | .ip? // empty'
  )"
fi

for cidr in "${allowed_ips[@]:-}"; do
  [ -n "$cidr" ] || continue
  if printf '%s\n' "$existing_acl" | grep -qxF "$cidr"; then
    note "$cidr : déjà autorisé"
  elif [ "$dry_run" -eq 1 ]; then
    run scw rdb acl add "$cidr" instance-id="$instance_id" \
      description="memobook" region="$region"
  else
    scw rdb acl add "$cidr" instance-id="$instance_id" \
      description="memobook" region="$region" >/dev/null
    note "$cidr : autorisé"
  fi
done

# --- Le certificat de l'autorité ------------------------------------------

say "Certificat TLS"

cert_path="$cert_dir/scaleway-rdb-$name.pem"

if [ "$dry_run" -eq 1 ]; then
  run scw rdb instance get-certificate "$instance_id" region="$region"
  note "→ $cert_path"
else
  mkdir -p "$cert_dir"
  scw rdb instance get-certificate "$instance_id" region="$region" > "$cert_path.tmp"

  # Selon la version du CLI, la commande rend le PEM brut ou un JSON qui le
  # contient. On accepte les deux plutôt que d'écrire un fichier illisible que
  # seule la première connexion révélerait.
  if head -1 "$cert_path.tmp" | grep -q "BEGIN CERTIFICATE"; then
    mv "$cert_path.tmp" "$cert_path"
  elif jq -er '.content // .certificate // empty' "$cert_path.tmp" > "$cert_path" 2>/dev/null; then
    rm -f "$cert_path.tmp"
  else
    echo "Certificat illisible, laissé dans $cert_path.tmp" >&2
    exit 1
  fi

  openssl x509 -in "$cert_path" -noout -subject -enddate >/dev/null
  note "écrit dans $cert_path"
  note "$(openssl x509 -in "$cert_path" -noout -enddate)"
fi

# --- Le DATABASE_URL -------------------------------------------------------

say "Connexion"

if [ "$dry_run" -eq 1 ]; then
  note "rien à afficher en dry-run."
  exit 0
fi

instance="$(scw rdb instance get "$instance_id" region="$region" -o json)"
port="$(jq -r '[.endpoints[] | select(.load_balancer != null) | .port] | first // 5432' <<<"$instance")"
ip="$(jq -r '[.endpoints[] | select(.load_balancer != null) | .ip] | first // empty' <<<"$instance")"

# Le nom DNS, pas l'IP : le certificat est émis pour lui, et c'est ce qui rend
# `sslmode=verify-full` vérifiable côté client.
host="rw-$instance_id.rdb.$region.scw.cloud"
abs_cert="$(cd "$(dirname "$cert_path")" && pwd)/$(basename "$cert_path")"

note "hôte : $host (IP $ip, port $port)"
note "base : $db_name — utilisateur : $db_user"

cat <<EOF

Pose ce DATABASE_URL dans les secrets du déploiement (jamais dans le dépôt) :

  DATABASE_URL="postgresql://$db_user:${password:-<mot-de-passe>}@$host:$port/$db_name?sslmode=require&sslcert=$abs_cert&sslaccept=strict&connection_limit=10"

Le certificat doit être déployé à ce chemin sur les machines API et worker.
Vérifie la connexion :

  PGSSLROOTCERT=$abs_cert psql "host=$host port=$port user=$db_user dbname=$db_name sslmode=verify-full"

Puis applique le schéma :

  cd backend && DATABASE_URL="…" npx prisma migrate deploy

EOF
