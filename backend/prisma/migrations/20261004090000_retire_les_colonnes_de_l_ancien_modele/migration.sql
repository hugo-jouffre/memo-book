-- Le second temps du crédit du jour (Hugo, 03/10/2026) : les colonnes des
-- étapes offertes et des limites de souvenirs quittent la base.
--
-- **À déployer seulement une fois `20261003090000_credit_du_jour` en service**
-- sur `api` et `worker` : c'est elle qui a retiré ces colonnes du code. Plus
-- aucun code déployé ne les lit, et l'ancien code qui tourne pendant la
-- bascule Railway est déjà celui du crédit du jour.
--
-- `IF EXISTS` : le schéma de test peut les avoir déjà perdues (une première
-- version de la migration précédente les supprimait).

-- AlterTable
ALTER TABLE "accounts" DROP COLUMN IF EXISTS "offeredSteps",
DROP COLUMN IF EXISTS "remainingSteps",
DROP COLUMN IF EXISTS "memoryPlan",
DROP COLUMN IF EXISTS "memoryUsed",
DROP COLUMN IF EXISTS "memoryPeriodStart";

-- DropEnum
DROP TYPE IF EXISTS "MemoryPlan";
