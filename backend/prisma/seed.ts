import { PrismaClient } from "@prisma/client";
import { generateDeviceToken, hashDeviceToken } from "../src/lib/auth.js";
import { hashPassword } from "../src/lib/password.js";

/**
 * Jeu de données de développement.
 *
 * Il ne sert pas qu'à faire du `curl` : c'est ce qui permet de **brancher
 * l'app sur de vraies données** sans attendre d'avoir raconté un voyage. Il
 * pose donc des comptes au mot de passe connu, et de quoi remplir les trois
 * écrans — accueil, voyage, profil — dans chacun de leurs états.
 *
 * Idempotent : relancé, il repart des mêmes comptes plutôt que d'en empiler
 * d'autres. Les carnets, eux, sont refaits à neuf.
 *
 * **Deux comptes, parce que le produit a deux paliers.** Le parcours freemium
 * ne se lit pas sur un seul profil : la pastille d'étapes offertes, le CTA lime
 * de l'accueil et le bouton d'abonnement n'existent que sur un compte à quota,
 * et la carte de statistiques ne s'ouvre que pour un abonné. Les avoir tous les
 * deux en base évite de croire qu'un écran est cassé alors qu'il montre l'autre
 * palier.
 */
const prisma = new PrismaClient();

/**
 * Le mot de passe des comptes de développement. **Ce n'est pas un secret** :
 * il est écrit ici, dans `docs/supabase.md`, et l'app s'en sert pour son bouton
 * « Testing mode ». Il n'ouvre que des comptes de démonstration.
 *
 * Le seed le **réécrit** à chaque passage, y compris sur un compte créé à la
 * main depuis l'app : c'est ce qui garantit que « Testing mode » entre, et
 * c'est la raison d'être de ces adresses.
 */
const TEST_PASSWORD = "memobook2026";

/** Le palier d'un compte : ce qui le fait payer, ou compter ses étapes. */
type Plan = "freeTrial" | "subscriber";

type TravellerSeed = {
  email: string;
  firstName: string;
  lastName: string;
  plan: Plan;
  /** Ce que le seed en dit à la fin, pour qu'on sache lequel ouvrir. */
  purpose: string;
};

/**
 * **Le compte de test de l'app.** C'est celui où mène « Testing mode », et
 * celui sur lequel les écrans se vérifient au quotidien.
 */
const TEST_ACCOUNT_EMAIL = "demo@memo-book.com";

const TRAVELLERS: TravellerSeed[] = [
  {
    email: TEST_ACCOUNT_EMAIL,
    firstName: "Hugo",
    lastName: "Jouffre",
    plan: "freeTrial",
    purpose: "compte de test de l'app — palier gratuit, celui de « Testing mode »",
  },
  {
    email: "demo@memobook.app",
    firstName: "Hugo",
    lastName: "Jouffre",
    plan: "subscriber",
    purpose: "le même contenu, vu par un abonné",
  },
];

const ROME_STEPS = [
  {
    number: 1,
    placeName: "Trastevere",
    startDate: new Date("2026-08-26T10:00:00Z"),
    endDate: new Date("2026-08-28T18:00:00Z"),
    transport: "plane" as const,
    souvenirs: [
      {
        placeLabel: "Trastevere, Rome",
        transcript:
          "On pose les sacs dans une chambre au troisième sans ascenseur, fenêtre sur une cour où quelqu'un fait sécher son linge. Le quartier sent la lessive et le basilic. On descend manger une pizza pliée en quatre, debout, en regardant passer les scooters.",
      },
      {
        placeLabel: "Santa Maria in Trastevere",
        transcript:
          "La place se remplit à la tombée du jour. Les mosaïques dorées de l'église attrapent les derniers rayons et virent au cuivre. Un type joue de la guitare sur les marches de la fontaine, tout le monde s'assoit par terre.",
      },
    ],
  },
  {
    number: 2,
    placeName: "Le Colisée",
    startDate: new Date("2026-08-29T09:00:00Z"),
    endDate: new Date("2026-08-30T19:00:00Z"),
    transport: "walk" as const,
    souvenirs: [
      {
        placeLabel: "Colisée, Rome",
        transcript:
          "Debout à sept heures pour éviter la queue, et on la fait quand même. Une fois dedans, le silence surprend : on s'attendait à une foire, c'est presque recueilli. On reste vingt minutes assis sur les gradins sans rien dire.",
      },
    ],
  },
  {
    number: 3,
    placeName: "Ostie antique",
    startDate: new Date("2026-09-01T10:00:00Z"),
    endDate: new Date("2026-09-01T17:00:00Z"),
    transport: "train" as const,
    souvenirs: [
      {
        placeLabel: "Ostia Antica",
        transcript:
          "Une demi-heure de train et plus personne. On marche dans des rues romaines vides, entre des pins parasols. On déjeune assis sur un mur, il fait trente-quatre degrés et on n'a croisé que six personnes en trois heures.",
      },
    ],
  },
];

/**
 * Pose un compte et tout ce qui pend après lui : ses voyages, ses étapes, ses
 * souvenirs, sa cagnotte, son abonnement et sa commande en cours.
 *
 * @param clara L'amie invitée sur les voyages. Elle est partagée entre les
 *   comptes plutôt que dupliquée : c'est elle qui fait apparaître les pastilles
 *   de compagnons, et deux Clara en base rendraient le jeu d'essai moins
 *   ressemblant que ce qu'il imite.
 */
async function seedTraveller(
  seed: TravellerSeed,
  clara: { id: string },
): Promise<{ token: string; balance: number }> {
  // ---------------------------------------------------------------------
  // Le compte, et l'appareil qui lui est rattaché
  // ---------------------------------------------------------------------

  // Le quota d'étapes et l'abonnement sont **les deux faces d'une seule
  // question** : un abonné n'a rien à décompter, un compte gratuit n'a rien à
  // facturer. Ils se posent donc ensemble, jamais l'un sans l'autre.
  const isSubscriber = seed.plan === "subscriber";
  // Trois offertes, trois restantes : le compte de test s'ouvre sur une
  // **première connexion**, rien de consommé. C'est l'état par lequel tout le
  // monde passe, et donc celui qu'on doit voir sans rien faire ; le bac à sable
  // de l'accueil rejoue les autres sans changer de compte.
  const quota = isSubscriber
    ? { offeredSteps: null, remainingSteps: null }
    : { offeredSteps: 3, remainingSteps: 3 };

  const identity = {
    emailVerifiedAt: new Date(),
    firstName: seed.firstName,
    lastName: seed.lastName,
    // Réécrit à chaque passage, sur un compte neuf comme sur un compte créé
    // depuis l'app : sans ça, « Testing mode » ne peut pas entrer.
    passwordHash: await hashPassword(TEST_PASSWORD),
    phoneNumber: "+33 6 12 34 56 78",
    addressLine1: "7 rue Simon Fryd",
    addressPostalCode: "69002",
    addressCity: "Lyon",
    addressCountry: "France",
    wantsNewsletter: true,
    ...quota,
  };

  const account = await prisma.account.upsert({
    where: { email: seed.email },
    update: identity,
    create: { email: seed.email, ...identity },
  });

  // On repart d'une ardoise propre côté carnets : un seed rejoué ne doit pas
  // empiler cinq fois le même voyage sur l'accueil.
  await prisma.memo.deleteMany({ where: { ownerAccountId: account.id } });

  const token = generateDeviceToken();
  await prisma.device.create({
    data: { tokenHash: hashDeviceToken(token), platform: "ios", accountId: account.id },
  });

  // Le propriétaire n'a pas de ligne de participant : `memos.ownerAccountId`
  // le dit, et `memo_members` ne porte que les invités.
  const guest = {
    accountId: clara.id,
    status: "active" as const,
    handle: "@clara_prn",
    acceptedAt: new Date(),
  };

  // ---------------------------------------------------------------------
  // Un voyage en cours, avec ses étapes et ses souvenirs
  // ---------------------------------------------------------------------

  const rome = await prisma.memo.create({
    data: {
      ownerAccountId: account.id,
      title: "Rome 2026",
      subtitle: "Dix jours à marcher et à manger",
      authors: "Hugo et Clara",
      theme: "City trip & découvertes",
      stage: "ongoing",
      destinationName: "Italie",
      destinationCountryCode: "IT",
      startDate: new Date("2026-08-26T00:00:00Z"),
      endDate: new Date("2026-09-15T00:00:00Z"),
      dayCount: 13,
      distanceKilometres: 87.4,
      narrationPace: "Tous les 2 jours",
      prompt: "Comment ça se passe à Trastevere ?",
      members: { create: [guest] },
    },
  });

  let memoryCount = 0;

  for (const step of ROME_STEPS) {
    const created = await prisma.memoStep.create({
      data: {
        memoId: rome.id,
        number: step.number,
        placeName: step.placeName,
        destinationName: "Italie",
        destinationCountryCode: "IT",
        startDate: step.startDate,
        endDate: step.endDate,
        transport: step.transport,
      },
    });

    for (const [index, souvenir] of step.souvenirs.entries()) {
      await prisma.entry.create({
        data: {
          memoId: rome.id,
          stepId: created.id,
          kind: "text",
          status: "ready",
          // Le seed s'arrête au texte brut : la rédaction est le travail du
          // job `redact`, et la simuler ici masquerait qu'il n'a pas tourné.
          redactionStatus: "pending",
          transcript: souvenir.transcript,
          placeLabel: souvenir.placeLabel,
          capturedAt: new Date(step.startDate.getTime() + index * 3_600_000),
        },
      });
      memoryCount += 1;
    }
  }

  await prisma.memo.update({
    where: { id: rome.id },
    data: { memoryCount, pageCount: memoryCount * 2 },
  });

  // ---------------------------------------------------------------------
  // Un voyage terminé et imprimable, et un voyage à venir
  // ---------------------------------------------------------------------

  const lisbonne = await prisma.memo.create({
    data: {
      ownerAccountId: account.id,
      title: "Lisbonne entre filles",
      theme: "voyage",
      stage: "past",
      destinationName: "Portugal",
      destinationCountryCode: "PT",
      startDate: new Date("2026-04-11T00:00:00Z"),
      endDate: new Date("2026-04-18T00:00:00Z"),
      dayCount: 7,
      distanceKilometres: 41.2,
      photoCount: 64,
      memoryCount: 22,
      pageCount: 58,
      isPrintable: true,
      members: { create: [guest] },
      renders: {
        create: [{ status: "ready", pdfUrl: "https://pdf.example.test/lisbonne.pdf" }],
      },
    },
  });

  await prisma.memo.create({
    data: {
      ownerAccountId: account.id,
      title: "Islande cet hiver",
      theme: "voyage",
      stage: "upcoming",
      destinationName: "Islande",
      destinationCountryCode: "IS",
      startDate: new Date("2026-12-20T00:00:00Z"),
      endDate: new Date("2026-12-30T00:00:00Z"),
    },
  });

  // ---------------------------------------------------------------------
  // Le profil : cagnotte, abonnement, commande en cours
  // ---------------------------------------------------------------------

  // La cagnotte se remplit par le registre, jamais en écrivant le solde à la
  // main — même dans un seed. C'est la seule façon de vérifier que le cache et
  // les écritures disent la même chose.
  const movements = [
    { amountCents: 5000, kind: "topup" as const, label: "Rechargement" },
    { amountCents: 1000, kind: "gift" as const, label: "Parrainage de Clara" },
    { amountCents: -1212, kind: "order_payment" as const, label: "Carnet Lisbonne" },
  ];

  // Le registre est refait à neuf : sans ça, un seed rejoué empilerait trois
  // mouvements de plus et le solde tripleraient à chaque passage.
  await prisma.walletEntry.deleteMany({ where: { accountId: account.id } });

  let balance = 0;
  for (const movement of movements) {
    balance += movement.amountCents;
    await prisma.walletEntry.create({
      data: { accountId: account.id, ...movement, balanceAfterCents: balance },
    });
  }

  await prisma.account.update({
    where: { id: account.id },
    data: { walletBalanceCents: balance },
  });

  await prisma.subscription.deleteMany({ where: { accountId: account.id } });

  // Un abonnement **seulement** pour le compte abonné. Le compte gratuit n'en a
  // pas du tout : c'est l'absence de ligne, et non un statut « résilié », qui
  // fait que l'app lui repropose l'offre.
  if (isSubscriber) {
    await prisma.subscription.create({
      data: {
        accountId: account.id,
        provider: "stripe",
        status: "active",
        priceCents: 299,
        interval: "week",
        renewsAt: new Date(Date.now() + 7 * 86_400_000),
      },
    });
  }

  const render = await prisma.render.findFirstOrThrow({ where: { memoId: lisbonne.id } });
  await prisma.printOrder.create({
    data: {
      memoId: lisbonne.id,
      renderId: render.id,
      status: "in_production",
      copies: 2,
      pageCount: 58,
      estimatedMinDays: 5,
      estimatedMaxDays: 10,
      shippingName: `${seed.firstName} ${seed.lastName}`,
      shippingLine1: "7 rue Simon Fryd",
      shippingPostalCode: "69002",
      shippingCity: "Lyon",
      shippingCountry: "France",
      amountCents: 1212,
      submittedAt: new Date(),
    },
  });

  return { token, balance };
}

async function main(): Promise<void> {
  // Une amie invitée sur les voyages : c'est elle qui fait apparaître les
  // pastilles de compagnons sur les couvertures. Un seul exemplaire, partagé
  // par les comptes.
  const clara = await prisma.account.upsert({
    where: { email: "clara@memobook.app" },
    update: {},
    create: { email: "clara@memobook.app", firstName: "Clara", lastName: "Perrin" },
  });

  const seeded: { seed: TravellerSeed; token: string; balance: number }[] = [];

  // En série et non en parallèle : les deux comptes écrivent dans les mêmes
  // tables, et le pooler de session ne gagnerait rien à les entrelacer.
  for (const traveller of TRAVELLERS) {
    const result = await seedTraveller(traveller, clara);
    seeded.push({ seed: traveller, ...result });
  }

  // ---------------------------------------------------------------------
  // Ce qui se pilote depuis la base
  // ---------------------------------------------------------------------

  await prisma.showcase.deleteMany({});
  await prisma.showcase.createMany({
    data: [
      {
        title: "Le tour de l'Islande de Marion",
        subtitle: "72 pages, 11 jours, 1 400 km",
        isActive: true,
        showOnWelcomeScreen: true,
        position: 0,
      },
      {
        title: "La première année de Jeanne",
        subtitle: "Un carnet de naissance, mois après mois",
        showOnWelcomeScreen: true,
        position: 1,
      },
      {
        title: "Six mois en Amérique du Sud",
        subtitle: "Le carnet le plus épais qu'on ait imprimé",
        showOnWelcomeScreen: true,
        position: 2,
      },
    ],
  });

  // La modale d'avis de la maquette, telle qu'elle se pousse sans livrer d'app.
  await prisma.feedbackCampaign.deleteMany({ where: { key: "avis-v1" } });
  await prisma.feedbackCampaign.create({
    data: {
      key: "avis-v1",
      title: "Peux-tu nous donner ton avis ?",
      subtitle:
        "MemoBook est en plein développement et ton avis compte beaucoup pour nous aider à améliorer l'app",
      isActive: true,
      questions: {
        create: [
          { position: 1, kind: "text", placeholder: "Ton commentaire..." },
          {
            position: 2,
            kind: "choice",
            config: {
              options: [
                { key: "a", label: "Option 1", hint: "Lorem Ipsum" },
                { key: "b", label: "Option 2", hint: "Lorem Ipsum" },
                { key: "c", label: "Option 3", hint: "Lorem Ipsum" },
              ],
            },
          },
          {
            position: 3,
            kind: "slider",
            prompt: "Questions avec un slider",
            config: { min: 0, max: 4, step: 1 },
          },
        ],
      },
    },
  });

  process.stdout.write(
    [
      "",
      "\x1b[1mJeu de données créé.\x1b[0m",
      "",
      `  Mot de passe des deux comptes : ${TEST_PASSWORD}`,
      "",
      ...seeded.flatMap(({ seed, token, balance }) => [
        `  \x1b[1m${seed.email}\x1b[0m — ${seed.purpose}`,
        `      cagnotte ${(balance / 100).toFixed(2)} €, token d'appareil ${token}`,
      ]),
      "",
      "  Chacun a trois voyages : un en cours (3 étapes, 4 souvenirs), un",
      "  terminé et imprimable, un à venir. Plus une commande en production et",
      "  la modale d'avis de la maquette.",
      "",
      "  Essai rapide :",
      "    TOKEN=$(curl -s localhost:3000/v1/auth/signin -H 'content-type: application/json' \\",
      `      -d '{"email":"${TEST_ACCOUNT_EMAIL}","password":"${TEST_PASSWORD}"}' | jq -r .token)`,
      '    curl -H "Authorization: Bearer $TOKEN" localhost:3000/v1/home | jq',
      '    curl -H "Authorization: Bearer $TOKEN" localhost:3000/v1/profile | jq',
      "",
    ].join("\n"),
  );
}

main()
  .catch((error: unknown) => {
    console.error(error);
    process.exit(1);
  })
  .finally(() => void prisma.$disconnect());
