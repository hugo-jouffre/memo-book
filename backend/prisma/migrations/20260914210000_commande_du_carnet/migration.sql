-- Le tunnel de commande du carnet, dessiné en sept étapes dans « 🤖 Claude
-- Import ». Ce que la base ne savait pas encore en tenir :
--
--  1. **La rapidité d'acheminement** (étape 4). Deux paliers, pas un délai en
--     jours : c'est ce que l'imprimeur vend, et c'est ce que l'écran propose.
--     `standard` est inclus dans le prix du carnet, `express` porte un
--     supplément. Les bornes réelles du suivi (`estimatedMinDays`,
--     `estimatedMaxDays`) restent posées par l'imprimeur à l'expédition —
--     annoncer « 2 à 3 jours » et livrer en cinq serait pire que de ne rien
--     promettre.
--
--  2. **La décomposition du prix** (étape 5). `amountCents` existait déjà,
--     mais un total seul ne redessine pas un récapitulatif. Trois colonnes
--     s'ajoutent, et elles sont **figées** plutôt que recalculables : un tarif
--     qui change demain ne doit pas réécrire ce qu'une commande d'hier
--     annonçait. L'égalité qui les lie est
--     `amountCents = itemsCents + shippingCents - walletAppliedCents`.
--
--  3. **La carte présentée** (étape 6). Nullable, parce qu'Apple Pay n'en
--     passe aucune, et en `SET NULL` parce que retirer une carte de son profil
--     ne doit pas emporter la commande qu'elle a réglée.
--
--  4. **Les options, exemplaire par exemplaire** (étape 3). C'est la seule
--     vraie table : l'écran laisse offrir le 2e carnet dans une autre version
--     que le 1er, donc les quatre options pendent du livre et non de la
--     commande. Elles se **copient** depuis `memos` au moment de commander —
--     changer le style de son carnet ensuite ne change pas un livre déjà parti
--     à l'impression.
--
-- Rien pour la cagnotte ni pour les cartes : `wallet_entries` (M4) et
-- `payment_cards` (M3) portaient déjà tout ce que les étapes 5 et 6 lisent.

-- 1. La rapidité d'acheminement.
CREATE TYPE "ShippingSpeed" AS ENUM ('standard', 'express');

ALTER TABLE "print_orders" ADD COLUMN     "shippingSpeed" "ShippingSpeed" NOT NULL DEFAULT 'standard',
ADD COLUMN     "itemsCents" INTEGER,
ADD COLUMN     "shippingCents" INTEGER,
ADD COLUMN     "walletAppliedCents" INTEGER,
ADD COLUMN     "paymentCardId" TEXT;

-- 3. La carte présentée. `SET NULL` : voir le commentaire d'en-tête.
ALTER TABLE "print_orders" ADD CONSTRAINT "print_orders_paymentCardId_fkey" FOREIGN KEY ("paymentCardId") REFERENCES "payment_cards"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- 4. Un exemplaire, ses quatre options. `position` part de 1 — « 1er Carnet ».
CREATE TABLE "print_order_copies" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "position" INTEGER NOT NULL,
    "decorationsEnabled" BOOLEAN NOT NULL DEFAULT true,
    "quizEnabled" BOOLEAN NOT NULL DEFAULT true,
    "freeZonesEnabled" BOOLEAN NOT NULL DEFAULT true,
    "crosswordEnabled" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "print_order_copies_pkey" PRIMARY KEY ("id")
);

-- Un seul jeu d'options par rang : c'est la base qui empêche deux « 1er
-- Carnet » de cohabiter dans la même commande, pas le code applicatif.
CREATE UNIQUE INDEX "print_order_copies_orderId_position_key" ON "print_order_copies"("orderId", "position");

ALTER TABLE "print_order_copies" ADD CONSTRAINT "print_order_copies_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "print_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;
