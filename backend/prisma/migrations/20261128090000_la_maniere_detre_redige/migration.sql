-- **La manière d'être rédigé**, et les indications du voyageur (T292).
--
-- Deux colonnes nullables sur `memos`. `redactionManner` à NULL se comporte
-- comme « spoken », la manière par défaut (`mannerOf`) : aucun carnet existant
-- ne change de rédaction du fait de cette migration, et aucune reprise n'est
-- déclenchée.
--
-- Rien à voir avec `styleKey`, qui est le style *visuel* du carnet : celle-ci
-- règle la façon d'écrire, et elle entre dans le prompt de rédaction.
ALTER TABLE "memos" ADD COLUMN "redactionManner" TEXT;
ALTER TABLE "memos" ADD COLUMN "redactionNotes" TEXT;
