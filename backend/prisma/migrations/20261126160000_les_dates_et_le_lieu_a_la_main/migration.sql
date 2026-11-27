-- **Les dates et le lieu qu'on fixe à la main** (T288).
--
-- Trois colonnes à côté de ce que la rédaction a compris, jamais à sa place :
-- la lecture du modèle reste intacte, et « revenir aux dates déduites » est un
-- simple NULL. Une relance de la rédaction réécrit `livedFromDay` et ne touche
-- pas à celles-ci.
ALTER TABLE "entries" ADD COLUMN "pinnedLivedFromDay" DATE;
ALTER TABLE "entries" ADD COLUMN "pinnedLivedToDay" DATE;
ALTER TABLE "entries" ADD COLUMN "pinnedPlaceName" TEXT;
