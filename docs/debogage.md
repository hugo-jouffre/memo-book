# Quand quelque chose ne marche pas

Un écran vide, une phrase sur le réseau, un bouton qui ne fait rien : trois
symptômes, une seule question — **est-ce l'app, le serveur, ou la base ?**

Ce document dit où regarder pour trancher, dans cet ordre. La règle générale :
on ne devine pas, on lit une ligne de log.

---

## 1. Le serveur : le suspect n°1

**Neuf fois sur dix, c'est lui.** Le back-end tourne en local, en `tsx watch` :
il redémarre à chaque fichier sauvegardé, et un redémarrage peut échouer.

### Le lancer là où on le voit

```bash
cd backend && npm run dev
```

**Dans un terminal ouvert, pas en arrière-plan.** Lancé avec `&` ou `nohup`, sa
sortie part dans un fichier que personne ne relit : il peut mourir sans que rien
ne le dise, et le seul symptôme visible sera un « Connexion impossible » dans
l'app, qui accuse le réseau. C'est exactement ce qui s'est produit le 08/09/2026.

Une fois lancé, chaque requête écrit deux lignes JSON — l'arrivée, puis le code
de statut et la durée :

```json
{"reqId":"req-18","req":{"method":"GET","url":"/v1/home"},"msg":"incoming request"}
{"reqId":"req-18","res":{"statusCode":200},"responseTime":387,"msg":"request completed"}
```

Pour les lire confortablement :

```bash
npm run dev | npx pino-pretty
```

### Est-il vivant ?

```bash
curl -s -o /dev/null -w "%{http_code}\n" localhost:3000/v1/showcases/welcome
```

`200` : il répond. `000` : rien n'écoute — relance-le.

### Ce qu'on trouve dans sa sortie

| Ce qu'on lit | Ce que ça veut dire |
|---|---|
| `EADDRINUSE ... :3000` | un autre process tient le port. `lsof -nP -iTCP:3000 -sTCP:LISTEN` dit lequel |
| `statusCode: 401` | jeton absent ou expiré — l'app va se faire déconnecter |
| `statusCode: 400` | corps de requête refusé par Zod ; la ligne dit quel champ |
| `statusCode: 500` | vraie erreur serveur ; la pile est juste au-dessus |
| `PrismaClientKnownRequestError` | la base a refusé. Migration manquante, ou `DATABASE_URL` qui pointe ailleurs |
| plus rien du tout | il est mort. La **dernière ligne** avant le silence est la cause |

> Le redémarrage de `tsx watch` envoie un `SIGTERM` **sans attendre la sortie**
> du process précédent : le nouveau pouvait tomber sur un `EADDRINUSE` et tuer
> le serveur. `src/server.ts` réessaie maintenant pendant 5 s en développement.
> Si tu vois « Port encore occupé », c'est ce garde-fou qui travaille.

---

## 2. L'app : la trace réseau

L'app écrit **une ligne par appel** dans le journal unifié d'Apple, en build de
développement uniquement (`#if DEBUG`, voir `NetworkLog`).

### Depuis Xcode

Lance avec ⌘R : les lignes défilent dans la console en bas (⌘⇧C si elle est
cachée). C'est le chemin le plus simple, et le seul qui donne aussi les points
d'arrêt.

### Sans Xcode

```bash
xcrun simctl spawn booted log stream --level debug --style compact \
  --predicate 'subsystem == "com.memobook.app"'
```

`--level debug` est **indispensable** : sans lui, seuls les échecs sortent, pas
les appels réussis.

Ce que ça donne :

```
→ POST /v1/auth/signin
← 200 POST /v1/auth/signin (810 ms)
→ GET /v1/home
← 200 GET /v1/home (1327 ms)
✗ POST /v1/auth/signin (1948 ms) — connexion refusée (rien n'écoute)
```

- `→` la requête part
- `←` le serveur a répondu ; un code hors 2xx/3xx sort en rouge
- `✗` l'appel n'a jamais abouti, et la fin de ligne dit pourquoi

**Deux lectures immédiates.** Aucune ligne `→` du tout : l'app n'a rien
demandé — le bug est dans l'écran, pas dans le réseau. Un `→` sans `←` : c'est
le serveur.

---

## 3. Ce que l'app raconte elle-même

En développement, l'app ne dit plus « Connexion impossible. Vérifie ton
réseau » : elle nomme la panne et donne la commande. Voir
`APIError.developerDiagnosis`.

| À l'écran | Cause | Geste |
|---|---|---|
| « Rien n'écoute sur localhost:3000 » | serveur arrêté | `cd backend && npm run dev` |
| « La connexion s'est coupée en cours de route » | serveur mort **pendant** l'appel | lire la fin de sa sortie |
| « n'a pas répondu à temps » | serveur bloqué, souvent sur la base | vérifier `DATABASE_URL` |
| « Pas de réseau » | là, c'est vraiment le wifi | — |
| « bloqué par ATS » | appel en clair refusé | `NSAllowsLocalNetworking`, dans `project.yml` |
| « Réponse inattendue du serveur » + un champ | le modèle Swift et `appSerializers.ts` ont divergé | aligner les deux — voir la règle dans `ios/CLAUDE.md` |

En build de production, ces phrases redeviennent la phrase neutre : elles ne
servent qu'à nous.

---

## 4. La base

```bash
cd backend && npx prisma studio      # parcourir les tables
npm run db:seed                      # tout remettre à plat
```

Le seed pose les deux comptes de test et leurs voyages. Après un `db:seed`, les
identifiants des voyages changent : une page de voyage ouverte avant renverra un
404, ce qui est normal.

---

## 5. Les trois commandes qui répondent le plus vite

```bash
curl -s -o /dev/null -w "%{http_code}\n" localhost:3000/v1/showcases/welcome
```
Le serveur répond-il ?

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```
Qui tient le port ?

```bash
curl -s localhost:3000/v1/auth/signin -H 'content-type: application/json' \
  -d '{"email":"demo@memo-book.com","password":"memobook2026"}'
```
La chaîne complète — serveur, base, mot de passe — en un appel. Un `token` en
retour, et le problème est dans l'app ; une erreur, et il est en dessous.
