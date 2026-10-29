-- **Un message peut contenir plusieurs étapes** (Hugo, 28/10/2026).
--
-- L'écrivain entend les moments distincts d'un même récit et les propose,
-- chacun citant mot pour mot sa tranche de la transcription. MEMO pose la
-- question dans le fil ; rien n'est découpé avant la réponse.
--
-- Nul par défaut : aucun souvenir déjà raconté n'a de proposition en attente.
ALTER TABLE "entries" ADD COLUMN "splitSuggestion" JSONB;
