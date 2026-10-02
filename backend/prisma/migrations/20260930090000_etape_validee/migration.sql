-- « Valider cette étape » : au même titre qu'Entry.validatedAt, le voyageur
-- confirme une étape et déclenche automatiquement une nouvelle génération du
-- carnet.
ALTER TABLE "memo_steps" ADD COLUMN "validatedAt" TIMESTAMP(3);
