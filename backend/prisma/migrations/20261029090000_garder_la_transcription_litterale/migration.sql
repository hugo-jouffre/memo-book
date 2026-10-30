-- **Garder la transcription littérale** plutôt que le texte rédigé (Hugo,
-- 28/10/2026 : « ajouter un toggle pour passer de la transcription littérale à
-- l'analyse et l'amélioration IA sur chaque message »).
--
-- Faux par défaut : rien ne change pour les souvenirs déjà racontés, qui
-- gardent le texte rédigé. C'est `finalTextOf` qui lit ce drapeau, et toute la
-- chaîne passe par elle — la fiche du fil, la composition du carnet, la
-- conversation.
ALTER TABLE "entries" ADD COLUMN "prefersTranscript" BOOLEAN NOT NULL DEFAULT false;
