-- **La corbeille de trente jours** (Hugo, 10/11/2026 — « j'ai toujours peur
-- qu'un voyage soit supprimé par inadvertance »).
--
-- Supprimer un voyage ne l'efface plus : ça pose cette date. Le voyage
-- disparaît aussitôt de partout — `visibleToAccount` exige `deletedAt IS
-- NULL` —, il ne reste visible qu'à son propriétaire dans la corbeille de
-- l'accueil, et il se restaure.
--
-- Trente jours plus tard, il s'efface pour de bon (`purgeDeletedMemos`) :
-- souvenirs, fichiers et traces chez les prestataires compris.
--
-- Nulle par défaut : aucun voyage existant n'est dans la corbeille.
ALTER TABLE "memos" ADD COLUMN "deletedAt" TIMESTAMP(3);

-- La corbeille lit les voyages jetés d'un propriétaire, et la purge balaie
-- ceux de plus de trente jours : les deux partent de cette colonne.
CREATE INDEX "memos_ownerAccountId_deletedAt_idx" ON "memos"("ownerAccountId", "deletedAt");
