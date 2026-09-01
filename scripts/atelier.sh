#!/usr/bin/env bash
#
# Ouvre l'atelier carnet : le serveur local, puis le navigateur.
#
#   ./scripts/atelier.sh
#   ./scripts/atelier.sh --port 4300
#
# Rien à installer : Node suffit, et la transcription passe par
# scripts/transcribe-whatsapp.sh, qui ne demande que curl.
#
set -euo pipefail

racine=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
port=4173
ouvrir=1

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--port) port="${2:?--port attend un numéro}"; shift 2 ;;
    --no-open) ouvrir=0; shift ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
done

command -v node >/dev/null || { echo "Node est requis (node -v)." >&2; exit 1; }

if [ "$ouvrir" -eq 1 ]; then
  # Le serveur met une fraction de seconde à écouter : on laisse le navigateur
  # partir derrière, plutôt que de faire attendre le terminal.
  (
    for _ in $(seq 1 40); do
      if curl -fsS -o /dev/null "http://127.0.0.1:$port/api/config" 2>/dev/null; then
        command -v open >/dev/null && open "http://127.0.0.1:$port" || true
        exit 0
      fi
      sleep 0.25
    done
  ) &
fi

exec node "$racine/tools/atelier/server.mjs" "--port=$port"
