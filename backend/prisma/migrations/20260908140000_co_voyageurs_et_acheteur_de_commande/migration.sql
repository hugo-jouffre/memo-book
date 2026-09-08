-- Un co-voyageur fait tout ce que fait le propriétaire — raconter, régler,
-- générer, commander. Seule la suppression du voyage reste au propriétaire.
--
-- Cela change une chose en base : **une commande n'est plus déductible du
-- voyage.** Deux personnes peuvent la passer, et chacune a sa propre cagnotte
-- et son propre abonnement (`wallet_entries` et `subscriptions` pendent d'un
-- compte, pas d'un voyage). La commande doit donc retenir qui l'a passée, sans
-- quoi il n'y aurait aucun moyen de savoir quelle cagnotte débiter le jour où
-- l'encaissement existera.

ALTER TABLE "print_orders" ADD COLUMN "orderedByAccountId" TEXT;

-- Les commandes déjà là ont forcément été passées par le propriétaire : à
-- l'époque, personne d'autre ne pouvait commander.
UPDATE "print_orders" AS o
SET "orderedByAccountId" = m."ownerAccountId"
FROM "memos" AS m
WHERE o."memoId" = m."id";

CREATE INDEX "print_orders_orderedByAccountId_createdAt_idx"
  ON "print_orders"("orderedByAccountId", "createdAt");

-- `SET NULL` : un compte supprimé ne doit pas emporter la commande d'un voyage
-- qui appartient à quelqu'un d'autre. La commande perd son acheteur, pas son
-- existence.
ALTER TABLE "print_orders" ADD CONSTRAINT "print_orders_orderedByAccountId_fkey"
  FOREIGN KEY ("orderedByAccountId") REFERENCES "accounts"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
