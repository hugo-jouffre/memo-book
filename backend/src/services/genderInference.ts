/**
 * Le genre d'une personne, **déduit de son prénom** tant qu'elle ne l'a pas
 * dit elle-même.
 *
 * L'app accorde deux ou trois mots — « Abonnée », « Abonné » — et ne sait pas
 * à qui elle parle : la maquette écrit au féminin, le code s'en tenait à la
 * forme non marquée (T76). Hugo a tranché le 17/09/2026 : on déduit du prénom,
 * et la personne corrige depuis son profil — femme, homme, ou « je ne préfère
 * pas répondre ». Ce qu'elle a choisi (`accounts.gender`) l'emporte toujours
 * sur ce qu'on devine ici.
 *
 * **Une liste, pas une règle.** Une terminaison ne dit rien de fiable —
 * Pierre, Alexandre et Jérôme finissent en « e » —, et une bibliothèque
 * tierce embarquerait des dizaines de milliers de prénoms pour un accord
 * grammatical. Les prénoms les plus portés en France suffisent ; un prénom
 * absent, ou porté par les deux (Camille, Dominique, Claude, Sacha, Charlie,
 * Lou, Alix, Noa, Eden), reste **sans réponse** : on n'accorde alors rien,
 * plutôt que de se tromper.
 */

export type Gender = "female" | "male" | "undisclosed";

// prettier-ignore
const FEMALE = [
  "marie", "jeanne", "louise", "emma", "alice", "chloe", "lea", "manon", "ines", "lina", "jade",
  "mila", "rose", "anna", "ambre", "julia", "lucie", "juliette", "zoe", "agathe", "lola", "nina",
  "eva", "romane", "sarah", "clara", "margaux", "léa", "chloé", "inès", "zoé", "léna", "lena",
  "adele", "adèle", "victoria", "victoire", "iris", "olivia", "mia", "sofia", "sophia", "elena",
  "eléna", "elise", "élise", "lisa", "maelys", "maëlys", "maeva", "maéva", "capucine",
  "apolline", "constance", "hortense", "eleonore", "eléonore", "éléonore", "charlotte",
  "mathilde", "pauline", "laura", "marion", "justine", "oceane", "océane", "melanie", "mélanie",
  "celine", "céline", "sandrine", "stephanie", "stéphanie", "nathalie", "isabelle", "valerie",
  "valérie", "sylvie", "catherine", "christine", "veronique", "véronique", "martine", "monique",
  "francoise", "françoise", "brigitte", "nicole", "jacqueline", "chantal", "annie", "michele",
  "michèle", "danielle", "helene", "hélène", "anne", "sophie", "julie", "aurelie", "aurélie",
  "elodie", "élodie", "emilie", "émilie", "audrey", "caroline", "virginie", "amandine",
  "delphine", "laetitia", "laëtitia", "jessica", "vanessa", "sabrina", "cindy", "morgane",
  "anais", "anaïs", "marine", "amelie", "amélie", "clemence", "clémence", "eloise", "éloïse",
  "faustine", "gabrielle", "garance", "heloise", "héloïse", "josephine", "joséphine", "leonie",
  "léonie", "louna", "luna", "lyna", "lucile", "madeleine", "margot", "marguerite", "melissa",
  "mélissa", "noemie", "noémie", "ophelie", "ophélie", "perrine", "philippine", "salome",
  "salomé", "solene", "solène", "suzanne", "tiphaine", "valentine", "yasmine", "alicia",
  "alexia", "angele", "angèle", "anouk", "aya", "bertille", "blanche", "candice", "celia",
  "célia", "diane", "elsa", "emeline", "émeline", "estelle", "fanny", "flavie", "flore",
  "florence", "gaelle", "gaëlle", "jenna", "joanna", "johanna", "judith", "laure", "lauren",
  "leila", "leïla", "lily", "lilou", "lise", "louisa", "ludivine", "maelle", "maëlle", "maud",
  "melina", "mélina", "myriam", "nadia", "nora", "oriane", "paloma", "roxane", "sabine", "samia",
  "sara", "selena", "séléna", "sixtine", "stella", "thais", "thaïs", "tessa", "tina", "yaelle",
  "yaëlle", "ysee", "ysée", "elisabeth", "élisabeth", "beatrice", "béatrice", "corinne", "edith",
  "édith", "genevieve", "geneviève", "ghislaine", "huguette", "josiane", "liliane", "lucienne",
  "marcelle", "mireille", "odette", "odile", "paulette", "pierrette", "renee", "renée", "simone",
  "solange", "therese", "thérèse", "yvette", "yvonne", "coline", "elea", "eléa", "éléa", "ella",
  "leana", "léana", "lila", "livia", "lyana", "maya", "meline", "méline", "naomi", "naomie",
  "nell", "nelly", "romy", "safia", "sana", "tiana", "yara", "zelie", "zélie", "axelle",
  "barbara", "bénédicte", "benedicte", "carole", "cecile", "cécile", "claire", "colette",
  "emmanuelle", "eugenie", "eugénie", "frederique", "frédérique", "isaure", "laurence",
  "leonore", "léonore", "maïlys", "mailys", "marianne", "murielle", "muriel", "nadege", "nadège",
  "patricia", "peggy", "rachel", "sandra", "severine", "séverine", "sonia", "valentina",
  "alexandra", "cassandra", "ninon", "louisette", "lucia", "prune", "roxanne", "wendy",
];

// prettier-ignore
const MALE = [
  "jean", "pierre", "michel", "philippe", "alain", "patrick", "nicolas", "christophe", "laurent",
  "eric", "éric", "frederic", "frédéric", "david", "stephane", "stéphane", "pascal", "olivier",
  "sebastien", "sébastien", "thierry", "julien", "bernard", "daniel", "jacques", "christian",
  "thomas", "alexandre", "gerard", "gérard", "andre", "andré", "guillaume", "vincent", "bruno",
  "antoine", "maxime", "francois", "françois", "didier", "jerome", "jérôme", "mathieu",
  "matthieu", "franck", "kevin", "kévin", "gilles", "romain", "florian", "anthony", "arnaud",
  "yves", "jean-pierre", "jean-claude", "jean-luc", "jean-marc", "jean-michel", "jean-paul",
  "jean-francois", "jean-françois", "jean-philippe", "jean-baptiste", "cedric", "cédric",
  "benjamin", "fabrice", "hugo", "lucas", "louis", "gabriel", "raphael", "raphaël", "arthur",
  "jules", "adam", "nathan", "leo", "léo", "paul", "mael", "maël", "noah", "ethan", "tom",
  "mathis", "theo", "théo", "enzo", "timeo", "timéo", "liam", "victor", "martin", "axel",
  "robin", "gaspard", "augustin", "oscar", "marius", "eliott", "elliot", "nolan", "aaron",
  "isaac", "noe", "noé", "leon", "léon", "come", "côme", "mohamed", "mohammed", "amir", "ayoub",
  "ibrahim", "ismael", "ismaël", "rayan", "yanis", "ilyes", "adrien", "alexis", "quentin",
  "clement", "clément", "valentin", "baptiste", "corentin", "simon", "samuel", "loic", "loïc",
  "damien", "cyril", "fabien", "gregory", "grégory", "jonathan", "ludovic", "michael", "mickael",
  "mickaël", "yannick", "xavier", "hervé", "herve", "marc", "denis", "serge", "rene", "rené",
  "roger", "robert", "raymond", "roland", "guy", "henri", "georges", "marcel", "maurice",
  "lucien", "fernand", "gaston", "gilbert", "joseph", "emile", "émile", "albert", "armand",
  "anatole", "basile", "benoit", "benoît", "bertrand", "charles", "constantin", "cyprien",
  "edgar", "edouard", "édouard", "eloi", "éloi", "emmanuel", "etienne", "étienne", "felix",
  "félix", "ferdinand", "gauthier", "geoffroy", "gregoire", "grégoire", "gustave", "hadrien",
  "hector", "hippolyte", "ivan", "jeremy", "jérémy", "jeremie", "jérémie", "joachim", "joris",
  "kilian", "killian", "lenny", "lorenzo", "loris", "mahé", "mahe", "malo", "marceau", "mattéo",
  "matteo", "milo", "nino", "octave", "oswald", "pablo", "patrice", "pierrick", "rafael", "remi",
  "rémi", "remy", "rémy", "ruben", "sami", "sofiane", "stanislas", "sylvain", "tanguy",
  "thibault", "thibaut", "tristan", "ugo", "ulysse", "wilfried", "william", "yann", "yoann",
  "yohan", "zacharie", "zachary", "amaury", "aurelien", "aurélien", "alban", "aymeric", "brice",
  "bastien", "cesar", "césar", "elias", "eliot", "erwan", "evan", "ewen", "gael", "gaël",
  "gaetan", "gaétan", "gaëtan", "ilan", "jason", "jordan", "kenzo", "logan", "mathys", "matis",
  "maxence", "mehdi", "nael", "naël", "nathanael", "nathanaël", "noam", "rayane", "ryan", "soan",
  "swan", "tiago", "titouan", "timothe", "timothé", "timothee", "timothée", "tony", "tobias",
  "wassim", "younes", "yassine", "francis", "jean-jacques", "jean-louis", "jean-marie",
  "jean-yves", "joel", "joël", "lionel", "noel", "noël", "regis", "régis", "richard", "rodolphe",
  "steve", "teddy", "theophile", "théophile", "wilson",
];

const FEMALE_SET = new Set(FEMALE);
const MALE_SET = new Set(MALE);

/**
 * Ramène un prénom à ce que les listes connaissent : minuscules, sans accents,
 * et seulement le **premier** prénom d'un composé écrit avec une espace
 * (« Marie Claire » → « marie ») — un composé au trait d'union, lui, est un
 * prénom à part entière (« jean-pierre »).
 */
function normalise(firstName: string): string[] {
  const trimmed = firstName.trim().toLowerCase();
  if (!trimmed) return [];
  const first = trimmed.split(/\s+/)[0] ?? trimmed;
  const bare = first.normalize("NFD").replace(/[̀-ͯ]/g, "");
  return bare === first ? [first] : [first, bare];
}

/**
 * Ce que le prénom laisse deviner. `undisclosed` dès qu'on ne sait pas :
 * prénom absent, inconnu des listes, ou porté par les deux.
 */
export function inferGender(firstName: string | null | undefined): Gender {
  if (!firstName) return "undisclosed";
  for (const candidate of normalise(firstName)) {
    const female = FEMALE_SET.has(candidate);
    const male = MALE_SET.has(candidate);
    if (female && !male) return "female";
    if (male && !female) return "male";
  }
  return "undisclosed";
}

/** Le genre à afficher : ce que la personne a dit, sinon ce qu'on devine. */
export function effectiveGender(
  stored: Gender | null | undefined,
  firstName: string | null | undefined,
): Gender {
  return stored ?? inferGender(firstName);
}
