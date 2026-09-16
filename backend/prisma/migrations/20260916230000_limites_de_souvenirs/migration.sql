-- « Limites de souvenirs » : le budget mensuel d'un compte qui raconte, et le
-- palier qu'il a choisi.
--
-- À ne pas confondre avec `offeredSteps` / `remainingSteps`, juste à côté : ce
-- sont les **étapes offertes**, le palier d'entrée, qui s'épuise une fois et
-- ouvre le paywall. Les limites de souvenirs, elles, se rechargent tous les
-- mois et se relèvent contre 3,99 €/mois.
--
-- Trois colonnes sur `accounts` plutôt qu'une table : il y a exactement une
-- ligne par compte, elle se lit toujours avec lui, et aucune requête ne
-- l'interroge seule. Le détail de ce qu'un vocal coûte face à un message vit
-- dans `services/memoryAllowance.ts` — une règle de tarification ne se range
-- pas dans un schéma.
CREATE TYPE "MemoryPlan" AS ENUM ('included', 'extended');

ALTER TABLE "accounts"
  ADD COLUMN "memoryPlan" "MemoryPlan" NOT NULL DEFAULT 'included',
  ADD COLUMN "memoryUsed" INTEGER NOT NULL DEFAULT 0,
  -- Le début du mois **glissant** en cours. `now()` pour les comptes existants :
  -- ils repartent avec un budget plein, ce qui est le seul choix défendable —
  -- personne n'a consommé quoi que ce soit avant que la colonne existe.
  ADD COLUMN "memoryPeriodStart" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
