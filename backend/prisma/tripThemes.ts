import type { PrismaClient } from "@prisma/client";

/**
 * Les thèmes de la première étape de « Créer un voyage » — « Contexte de ton
 * voyage » —, dans l'ordre où la rangée les montre. Arrêtés par Hugo le
 * 14/09/2026.
 *
 * **« Autre » est toujours dernier**, et c'est un choix de produit : on préfère
 * un thème précis, le champ libre est la porte de sortie. La route l'impose
 * quelle que soit sa position (`isOther` d'abord dans le tri), le seed le pose
 * quand même en dernier pour qu'un lecteur de la table voie la même chose que
 * l'app.
 *
 * Le libellé part **tel quel** dans `memos.theme` : c'est du texte lu par
 * l'agent de rédaction, pas une clé. Le renommer ici renomme ce que l'agent
 * lira sur les voyages créés ensuite — pas sur les anciens.
 */
export const TRIP_THEMES = [
  { slug: "nature-aventure", emoji: "🏔️", name: "Nature & aventure" },
  { slug: "grands-voyages", emoji: "🌍", name: "Grands voyages / exploration" },
  { slug: "a-deux", emoji: "❤️", name: "Voyages à deux" },
  { slug: "en-famille", emoji: "👨‍👩‍👧‍👦", name: "Voyages en famille" },
  { slug: "entre-amis", emoji: "👯", name: "Voyages entre amis" },
  { slug: "city-trips", emoji: "🏙️", name: "City trips & découverte" },
  { slug: "gastronomie", emoji: "🍷", name: "Gastronomie & art de vivre" },
  { slug: "vacances-detente", emoji: "☀️", name: "Vacances & détente" },
  { slug: "evenementiels", emoji: "🎉", name: "Voyages événementiels" },
  { slug: "etudes-travail", emoji: "💼", name: "Études / Travail" },
  // Le seul sans émoji dans la liste de Hugo : la bulle est celle que l'app
  // dessinait déjà pour le champ libre.
  { slug: "autre", emoji: "💬", name: "Autre", isOther: true },
] as const;

/**
 * Pose les thèmes, ou les remet d'équerre : **idempotent**, comme le reste du
 * seed. Un thème retiré de la liste n'est pas supprimé — il est éteint
 * (`isActive: false`), pour que les voyages qui le citent gardent un texte qui
 * existe quelque part.
 */
export async function seedTripThemes(prisma: PrismaClient): Promise<number> {
  const kept = new Set<string>();

  for (const [position, theme] of TRIP_THEMES.entries()) {
    const data = {
      emoji: theme.emoji,
      name: theme.name,
      isOther: "isOther" in theme ? theme.isOther : false,
      position,
      isActive: true,
    };
    await prisma.tripTheme.upsert({
      where: { slug: theme.slug },
      update: data,
      create: { slug: theme.slug, ...data },
    });
    kept.add(theme.slug);
  }

  await prisma.tripTheme.updateMany({
    where: { slug: { notIn: [...kept] } },
    data: { isActive: false },
  });

  return TRIP_THEMES.length;
}
