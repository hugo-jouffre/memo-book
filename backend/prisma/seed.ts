import { PrismaClient } from "@prisma/client";
import { generateDeviceToken, hashDeviceToken } from "../src/lib/auth.js";
import { hashPassword } from "../src/lib/password.js";

/**
 * Jeu de données de développement.
 *
 * Il ne sert pas qu'à faire du `curl` : c'est ce qui permet de **brancher
 * l'app sur de vraies données** sans attendre d'avoir raconté un voyage. Il
 * pose donc un compte avec un mot de passe connu, et de quoi remplir les trois
 * écrans — accueil, voyage, profil — dans chacun de leurs états.
 *
 * Idempotent : relancé, il repart du même compte plutôt que d'en empiler un
 * deuxième. Les carnets, eux, sont refaits à neuf.
 */
const prisma = new PrismaClient();

const DEMO = {
  email: "demo@memobook.app",
  password: "memobook2026",
  firstName: "Hugo",
  lastName: "Jouffre",
} as const;

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

async function main(): Promise<void> {
  // ---------------------------------------------------------------------
  // Le compte, et l'appareil qui lui est rattaché
  // ---------------------------------------------------------------------

  const account = await prisma.account.upsert({
    where: { email: DEMO.email },
    update: {},
    create: {
      email: DEMO.email,
      emailVerifiedAt: new Date(),
      firstName: DEMO.firstName,
      lastName: DEMO.lastName,
      passwordHash: await hashPassword(DEMO.password),
      phoneNumber: "+33 6 12 34 56 78",
      addressLine1: "7 rue Simon Fryd",
      addressPostalCode: "69002",
      addressCity: "Lyon",
      addressCountry: "France",
      wantsNewsletter: true,
      offeredSteps: 3,
      remainingSteps: 2,
    },
  });

  // On repart d'une ardoise propre côté carnets : un seed rejoué ne doit pas
  // empiler cinq fois le même voyage sur l'accueil.
  await prisma.memo.deleteMany({ where: { ownerAccountId: account.id } });

  const token = generateDeviceToken();
  const device = await prisma.device.create({
    data: { tokenHash: hashDeviceToken(token), platform: "ios", accountId: account.id },
  });

  // Une amie invitée sur les voyages : c'est elle qui fait apparaître les
  // pastilles de compagnons sur les couvertures.
  const clara = await prisma.account.upsert({
    where: { email: "clara@memobook.app" },
    update: {},
    create: { email: "clara@memobook.app", firstName: "Clara", lastName: "Perrin" },
  });

  const owner = { accountId: account.id, role: "owner" as const, status: "active" as const };
  const guest = {
    accountId: clara.id,
    role: "guest" as const,
    status: "active" as const,
    handle: "@clara_prn",
    acceptedAt: new Date(),
  };

  // ---------------------------------------------------------------------
  // Un voyage en cours, avec ses étapes et ses souvenirs
  // ---------------------------------------------------------------------

  const rome = await prisma.memo.create({
    data: {
      deviceId: device.id,
      ownerAccountId: account.id,
      title: "Rome 2026",
      subtitle: "Dix jours à marcher et à manger",
      authors: "Hugo et Clara",
      theme: "City trip & découvertes",
      stage: "ongoing",
      destinationName: "Italie",
      destinationCountryCode: "IT",
      destinationCity: "Rome",
      startDate: new Date("2026-08-26T00:00:00Z"),
      endDate: new Date("2026-09-15T00:00:00Z"),
      dayCount: 13,
      distanceKilometres: 87.4,
      narrationPace: "Tous les 2 jours",
      prompt: "Comment ça se passe à Trastevere ?",
      members: { create: [owner, guest] },
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
      deviceId: device.id,
      ownerAccountId: account.id,
      title: "Lisbonne entre filles",
      theme: "voyage",
      stage: "past",
      destinationName: "Portugal",
      destinationCountryCode: "PT",
      destinationCity: "Lisbonne",
      startDate: new Date("2026-04-11T00:00:00Z"),
      endDate: new Date("2026-04-18T00:00:00Z"),
      dayCount: 7,
      distanceKilometres: 41.2,
      photoCount: 64,
      memoryCount: 22,
      pageCount: 58,
      isPrintable: true,
      members: { create: [owner, guest] },
      renders: {
        create: [{ status: "ready", pdfUrl: "https://pdf.example.test/lisbonne.pdf" }],
      },
    },
  });

  await prisma.memo.create({
    data: {
      deviceId: device.id,
      ownerAccountId: account.id,
      title: "Islande cet hiver",
      theme: "voyage",
      stage: "upcoming",
      destinationName: "Islande",
      destinationCountryCode: "IS",
      destinationCity: "Reykjavik",
      startDate: new Date("2026-12-20T00:00:00Z"),
      endDate: new Date("2026-12-30T00:00:00Z"),
      members: { create: [owner] },
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
      shippingName: `${DEMO.firstName} ${DEMO.lastName}`,
      shippingLine1: "7 rue Simon Fryd",
      shippingPostalCode: "69002",
      shippingCity: "Lyon",
      shippingCountry: "France",
      amountCents: 1212,
      submittedAt: new Date(),
    },
  });

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
      "  Connecte l'app avec ce compte :",
      `    adresse      ${DEMO.email}`,
      `    mot de passe ${DEMO.password}`,
      "",
      "  Trois voyages : un en cours (3 étapes, 4 souvenirs), un terminé et",
      "  imprimable, un à venir. Une commande en production, une cagnotte à",
      `  ${(balance / 100).toFixed(2)} €, et la modale d'avis de la maquette.`,
      "",
      `  Token d'appareil : ${token}`,
      "",
      "  Essai rapide :",
      "    TOKEN=$(curl -s localhost:3000/v1/auth/signin -H 'content-type: application/json' \\",
      `      -d '{"email":"${DEMO.email}","password":"${DEMO.password}"}' | jq -r .token)`,
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
