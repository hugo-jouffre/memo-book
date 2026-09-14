/**
 * Combien de connexions un process a le droit d'ouvrir vers Postgres.
 *
 * Sur Supabase, le *Session pooler* n'accepte que **15 clients** à la fois pour
 * tout le projet. Sans plafond, un seul back-end en dépasse à lui seul : Prisma
 * ouvre par défaut `2 × cœurs + 1` connexions et pg-boss en prend 10 de plus.
 * Deux serveurs de développement lancés par mégarde, un `prisma studio`
 * ouvert à côté, et la 16ᵉ connexion est refusée — chaque requête tombe alors
 * en 500 « Erreur interne du serveur », y compris à l'écran d'accueil.
 *
 * On répartit donc un budget fixe et petit entre les deux clients, de manière
 * à tenir plusieurs processus dans les 15. Les valeurs sont volontairement
 * basses : ce back-end sert une app mobile, pas un site à fort trafic.
 */
export interface PoolBudget {
  /** Connexions du client Prisma, qui sert les routes HTTP. */
  prisma: number;
  /** Connexions de pg-boss, qui ne fait que déposer et relever des jobs. */
  boss: number;
}

export function splitPoolBudget(total: number): PoolBudget {
  // pg-boss n'a besoin que de peu : une pour écouter, une pour publier.
  const boss = Math.max(1, Math.min(2, total - 1));
  return { prisma: Math.max(1, total - boss), boss };
}

/**
 * Ajoute `connection_limit` à l'URL Prisma si elle ne le porte pas déjà. Une
 * URL qui le fixe explicitement garde sa valeur : c'est le moyen de déroger au
 * cas par cas sans toucher au code.
 */
export function withConnectionLimit(databaseUrl: string, limit: number): string {
  const url = new URL(databaseUrl);
  if (!url.searchParams.has("connection_limit")) {
    url.searchParams.set("connection_limit", String(limit));
  }
  // Prisma attend aussi les requêtes qui patientent au-delà de 10 s (défaut) :
  // on garde ce défaut, il suffit à lisser une rafale au lancement de l'app.
  return url.toString();
}

/**
 * Reconnaît les erreurs qui veulent dire « la base n'est pas joignable en ce
 * moment » — pool saturé, serveur injoignable, attente de connexion expirée —
 * par opposition à un bug dans une requête. La distinction compte : la
 * première se règle en réessayant, la seconde non, et l'app ne doit pas
 * afficher le même message pour les deux.
 */
export function isDatabaseUnavailable(error: unknown): boolean {
  if (!(error instanceof Error)) return false;

  const code = (error as { code?: unknown }).code;
  // P1001/P1002 : serveur injoignable ou délai dépassé. P1017 : connexion
  // fermée par le serveur. P2024 : le pool Prisma n'a pas rendu de connexion
  // dans le délai.
  if (typeof code === "string" && ["P1001", "P1002", "P1017", "P2024"].includes(code)) {
    return true;
  }

  // Erreurs d'initialisation Prisma et erreurs brutes du pooler Supabase, qui
  // remontent avec leur libellé en clair.
  const text = `${error.name} ${error.message}`;
  return (
    error.name === "PrismaClientInitializationError" ||
    /max clients reached/i.test(text) ||
    /EMAXCONNSESSION/i.test(text) ||
    /Timed out fetching a new connection/i.test(text)
  );
}
