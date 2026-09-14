# syntax=docker/dockerfile:1

# L'image de l'API et du worker MemoBook. Les deux process sortent de la même
# image : seule la commande change (voir le bas du fichier).
#
# ⚠️ Le contexte de build est la **racine du dépôt**, pas `backend/` :
#
#     docker build -f backend/Dockerfile -t memobook-api .
#
# `src/lib/templates.ts` résout `templates/` et `agents/` en remontant de trois
# crans depuis `dist/lib/`, c'est-à-dire à la racine du dépôt. Une image
# construite depuis `backend/` se construirait sans broncher et tomberait au
# premier carnet, faute de gabarit et de règles de rédaction.

# ---------------------------------------------------------------- construction

FROM node:22-slim AS build
WORKDIR /app/backend

# Prisma engendre puis charge son client en passant par OpenSSL : absent de
# l'image slim, et le client ne se génère pas.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

COPY backend/package.json backend/package-lock.json ./
RUN npm ci

# `prisma generate` avant la compilation : le client engendré est ce que
# `@prisma/client` charge, et rien ne le recrée tout seul.
COPY backend/prisma ./prisma
RUN npx prisma generate

COPY backend/tsconfig.json backend/tsconfig.build.json ./
COPY backend/src ./src
RUN npm run build

# -------------------------------------------------------------------- exécution

FROM node:22-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app/backend

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Le client Prisma engendré vit dans `node_modules` et ne survit pas au
# `npm ci` ci-dessus : on le reprend de l'étape de construction.
COPY --from=build /app/backend/node_modules/.prisma ./node_modules/.prisma
COPY --from=build /app/backend/dist ./dist
COPY backend/prisma ./prisma

# Ce que le code lit à la racine du dépôt : voir l'avertissement en tête de
# fichier. Trois chemins aujourd'hui — `templates/` et `agents/` par
# `lib/templates.ts`, `assets/maps/countries.json` par `services/mapSvg.ts`.
#
# `assets/` est copié en entier (2,5 Mo) plutôt que le seul `maps/` : le
# couplage à la racine a déjà surpris trois fois, et une copie exhaustive coûte
# moins cher qu'un quatrième chemin découvert en production.
COPY templates /app/templates
COPY agents /app/agents
COPY assets /app/assets

USER node
EXPOSE 3000

# L'API. Le worker, c'est la même image avec `node dist/worker.js` — c'est
# l'hébergeur qui pose la commande du second process.
CMD ["node", "dist/server.js"]
