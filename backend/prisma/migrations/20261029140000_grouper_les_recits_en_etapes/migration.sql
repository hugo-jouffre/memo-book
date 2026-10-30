-- **Un message n'est pas toujours une étape** (Hugo, 28/10/2026).
--
-- `continuesPreviousStep` est ce que la rédaction a compris : ce récit
-- prolonge le précédent, les deux ne font qu'une étape. `separatedByTraveller`
-- est ce que le voyageur a dit depuis la carte de l'étape, et il passe devant.
--
-- Les deux sont faux par défaut : rien ne bouge pour les voyages déjà
-- racontés, qui gardent une étape par récit.
ALTER TABLE "entries" ADD COLUMN "continuesPreviousStep" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "entries" ADD COLUMN "separatedByTraveller" BOOLEAN NOT NULL DEFAULT false;
