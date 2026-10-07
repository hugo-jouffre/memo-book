import { describe, expect, it } from "vitest";
import {
  planNotifications,
  planTripEndEmail,
  selectNotifications,
  type PlannedNotification,
  type PlannerAccount,
  type PlannerDelivery,
  type PlannerTrip,
} from "./notificationPlanner.js";
import type { SchoolHolidayPeriod } from "./schoolHolidays.js";

function trip(overrides: Partial<PlannerTrip> = {}): PlannerTrip {
  return {
    id: "rome",
    title: "Rome 2026",
    city: "Rome",
    startsOn: "2026-10-01",
    endsOn: "2026-10-12",
    createdOn: "2026-09-28",
    storedStage: "ongoing",
    narrationPace: "every_two_days",
    notificationsEnabled: true,
    notifyWritingReminder: true,
    notifyNewStory: true,
    notifyWeeklyDigest: true,
    notifyTripEnd: true,
    prompt: null,
    storyCount: 2,
    lastStoryOn: "2026-10-03",
    isOwner: true,
    hasOrder: false,
    estimateCents: 4290,
    memberCount: 1,
    newFromOthers: null,
    weekStories: 0,
    weekPhotos: 0,
    ...overrides,
  };
}

function account(overrides: Partial<PlannerAccount> = {}): PlannerAccount {
  return {
    id: "camille",
    birthDate: null,
    schoolCalendar: null,
    renewsAtApple: false,
    renewsOn: null,
    hasEmail: true,
    usedRecently: false,
    trips: [trip()],
    deliveries: [],
    ...overrides,
  };
}

const kinds = (notifications: PlannedNotification[]) => notifications.map((n) => n.kind);

const toussaintB: SchoolHolidayPeriod = {
  zone: "B",
  label: "Vacances de la Toussaint",
  schoolYear: "2026-2027",
  startsOn: "2026-10-17",
  endsOn: "2026-11-02",
};

/** L'hiver, étalé sur trois semaines : A part la deuxième, B la première, C la troisième. */
const winter = (["A", "B", "C"] as const).map(
  (zone, index): SchoolHolidayPeriod => ({
    zone,
    label: "Vacances d'Hiver",
    schoolYear: "2026-2027",
    startsOn: ["2027-02-13", "2027-02-06", "2027-02-20"][index]!,
    endsOn: ["2027-03-01", "2027-02-22", "2027-03-08"][index]!,
  }),
);

/** Un abonnement App Store qui se renouvellera le 1er novembre. */
const armed = { renewsAtApple: true, renewsOn: "2026-11-01" };

describe("la fin du voyage", () => {
  it("part le jour de la date de fin, vers l'aperçu du carnet, avec son estimation", () => {
    const due = planNotifications(account(), [], "2026-10-12").find((n) => n.kind === "trip_end");

    // L'aperçu, d'où le carnet se commande : la cagnotte qui l'ouvrait est
    // retirée (06/10/2026).
    expect(due).toMatchObject({ link: "memobook://trips/rome/preview", memoId: "rome", family: "billing" });
    expect(due?.title).toBe("Ton voyage à Rome se termine aujourd’hui");
    expect(due?.body).toMatch(/^Ton carnet est estimé à 42,90\s€\. Il n’attend plus que ta commande\.$/);
    // Sans abonnement, rien à couper — et plus rien n'est déduit du carnet.
    expect(due?.body).not.toContain("abonnement");
    expect(due?.body).not.toContain("dédui");
  });

  it("invite doucement l'abonné App Store à couper son abonnement, et dit jusqu'à quand il garde l'illimité", () => {
    const due = planNotifications(account(armed), [], "2026-10-12").find((n) => n.kind === "trip_end");

    expect(due?.body).toMatch(
      /^Ton abonnement ne te sert plus d’ici ton prochain voyage \? Coupe-le en un geste depuis l’accueil, tu gardes l’illimité jusqu’au 1er novembre\. Ton carnet est estimé à 42,90\s€\./,
    );
    // Plus aucun abonnement ne s'arrête seul (03/10/2026).
    expect(due?.body).not.toContain("automatiquement");
  });

  it("nomme la fin de la période payée sans la chiffrer, tant qu'Apple ne l'a pas datée", () => {
    const due = planNotifications(account({ renewsAtApple: true }), [], "2026-10-12").find(
      (n) => n.kind === "trip_end",
    );
    expect(due?.body).toContain("tu gardes l’illimité jusqu’à la fin de la période payée.");
  });

  it("ne parle pas de l'abonnement quand un autre voyage le fait encore servir", () => {
    const camille = account({
      ...armed,
      trips: [trip(), trip({ id: "lisbonne", startsOn: "2026-11-02", endsOn: "2026-11-09" })],
    });
    const due = planNotifications(camille, [], "2026-10-12").find((n) => n.kind === "trip_end");
    expect(due?.body).not.toContain("abonnement");
  });

  it("part pour un carnet vide s'il y a un abonnement à couper, et se tait sinon", () => {
    const empty = { trips: [trip({ storyCount: 0, lastStoryOn: null })] };
    const due = planNotifications(account({ ...armed, ...empty }), [], "2026-10-12").find((n) => n.kind === "trip_end");
    expect(due?.body).toBe(
      "Ton abonnement ne te sert plus d’ici ton prochain voyage ? Coupe-le en un geste depuis l’accueil, tu gardes l’illimité jusqu’au 1er novembre.",
    );
    expect(kinds(planNotifications(account(empty), [], "2026-10-12"))).not.toContain("trip_end");
  });

  it("se tait si l'alerte de fin de voyage est coupée, ou le voyage muet", () => {
    expect(kinds(planNotifications(account({ trips: [trip({ notifyTripEnd: false })] }), [], "2026-10-12"))).not.toContain(
      "trip_end",
    );
    expect(
      kinds(planNotifications(account({ trips: [trip({ notificationsEnabled: false })] }), [], "2026-10-12")),
    ).not.toContain("trip_end");
  });
});

describe("le rappel avant le renouvellement", () => {
  // Rome a fini le 12 ; l'abonnement se renouvelle le 20.
  const renewing = { renewsAtApple: true, renewsOn: "2026-10-20" };
  const reminderOn = (overrides: Partial<PlannerAccount>, date: string) =>
    planNotifications(account({ ...renewing, ...overrides }), [], date).find((n) => n.kind === "renewal_reminder");

  it("part trois jours avant, une fois par période, vers la feuille de l'abonnement", () => {
    expect(reminderOn({}, "2026-10-17")).toMatchObject({
      dedupeKey: "camille:renewal_reminder:2026-10-20",
      link: "memobook://subscription",
      memoId: null,
      family: "billing",
      earliestHour: 10,
      title: "Ton abonnement se renouvelle dans 3 jours",
      body: "Pas de voyage en cours : si tu n’en as plus besoin, coupe-le en un geste. Tu gardes l’illimité jusqu’au 20 octobre.",
    });
  });

  it("rattrape une passe manquée deux jours avant, jamais la veille : Apple veut vingt-quatre heures", () => {
    const twoDaysBefore = reminderOn({}, "2026-10-18");
    expect(twoDaysBefore?.title).toBe("Ton abonnement se renouvelle dans 2 jours");
    // La même clé : s'il est parti à J-3, il ne repart pas à J-2.
    expect(twoDaysBefore?.dedupeKey).toBe("camille:renewal_reminder:2026-10-20");
    expect(reminderOn({}, "2026-10-19")).toBeUndefined();
    expect(reminderOn({}, "2026-10-16")).toBeUndefined();
  });

  it("se tait quand un voyage court, ou commence avant le renouvellement — le jour même compris", () => {
    const running = { trips: [trip({ endsOn: "2026-10-18" })] };
    expect(reminderOn(running, "2026-10-17")).toBeUndefined();

    const next = (startsOn: string) => ({
      trips: [trip(), trip({ id: "lisbonne", startsOn, endsOn: "2026-10-27" })],
    });
    expect(reminderOn(next("2026-10-20"), "2026-10-17")).toBeUndefined();
    expect(reminderOn(next("2026-10-21"), "2026-10-17")).toBeDefined();
  });

  it("se tait quand la fin d'un voyage vient de le dire", () => {
    const told = (sentOn: string): Partial<PlannerAccount> => ({
      deliveries: [{ kind: "trip_end", dedupeKey: "camille:trip_end:rome", sentOn, opened: false }],
    });
    expect(reminderOn(told("2026-10-15"), "2026-10-17")).toBeUndefined();
    expect(reminderOn(told("2026-10-14"), "2026-10-17")).toBeDefined();
  });

  // R51 (03/10/2026) : l'e-mail de fin de voyage n'est pas dans le journal que
  // lit le planificateur. Notification de fin coupée, le rappel tombait le
  // jour même de l'e-mail.
  it("se tait les jours de l'e-mail de fin de voyage, même quand la notification de fin est coupée", () => {
    // Rome finit le 3 novembre, alerte de fin coupée ; renouvellement le 7.
    const ended = { renewsOn: "2026-11-07", trips: [trip({ endsOn: "2026-11-03", notifyTripEnd: false })] };
    expect(kinds(planNotifications(account({ ...renewing, ...ended }), [], "2026-11-03"))).not.toContain("trip_end");
    expect(planTripEndEmail(account({ ...renewing, ...ended }), "2026-11-04", 10)?.trip.id).toBe("rome");
    expect(reminderOn(ended, "2026-11-04")).toBeUndefined();
    expect(reminderOn(ended, "2026-11-05")).toBeUndefined();

    // Quatre jours après la fin, l'e-mail ne part plus : le rappel reprend.
    expect(reminderOn({ ...ended, renewsOn: "2026-11-10" }, "2026-11-07")).toBeDefined();

    // Un voyage qui s'annonce après le renouvellement : pas d'e-mail, et le
    // rappel est seul à parler.
    const next = {
      ...ended,
      trips: [...ended.trips, trip({ id: "lisbonne", startsOn: "2026-11-08", endsOn: "2026-11-15" })],
    };
    expect(planTripEndEmail(account({ ...renewing, ...next }), "2026-11-04", 10)).toBeNull();
    expect(reminderOn(next, "2026-11-04")).toBeDefined();
  });

  // S08 (03/10/2026) : un compte entré par Apple sans adresse certifiée ne
  // reçoit jamais l'e-mail — le rappel ne se tait pas pour lui.
  it("parle quand même les jours de l'e-mail à un compte sans adresse, qui ne le recevra pas", () => {
    // Rome finit le 3 novembre, alerte de fin coupée ; renouvellement le 7.
    const silent = {
      hasEmail: false,
      renewsOn: "2026-11-07",
      trips: [trip({ endsOn: "2026-11-03", notifyTripEnd: false })],
    };
    expect(planTripEndEmail(account({ ...renewing, ...silent }), "2026-11-04", 10)).toBeNull();
    expect(reminderOn(silent, "2026-11-04")).toMatchObject({
      dedupeKey: "camille:renewal_reminder:2026-11-07",
      title: "Ton abonnement se renouvelle dans 3 jours",
    });
  });

  // R52 (03/10/2026) : l'ancien abonnement à la semaine, encore honoré, se
  // renouvelle tous les sept jours — un rappel par période en ferait un par
  // semaine, et ce jour-là rien d'autre ne partirait.
  describe("espacé de quatre semaines", () => {
    const sent = (sentOn: string, renewsOn: string): PlannerDelivery => ({
      kind: "renewal_reminder",
      dedupeKey: `camille:renewal_reminder:${renewsOn}`,
      sentOn,
      opened: false,
    });

    it("n'en envoie qu'un toutes les quatre semaines à l'ancien abonnement à la semaine", () => {
      expect(reminderOn({}, "2026-10-17")).toBeDefined();
      const deliveries = [sent("2026-10-17", "2026-10-20")];
      for (const [renewsOn, today] of [
        ["2026-10-27", "2026-10-24"],
        ["2026-11-03", "2026-10-31"],
        ["2026-11-10", "2026-11-07"],
      ] as const) {
        expect(reminderOn({ renewsOn, deliveries }, today), renewsOn).toBeUndefined();
      }
      expect(reminderOn({ renewsOn: "2026-11-17", deliveries }, "2026-11-14")).toBeDefined();
    });

    it("n'en fait perdre aucun à l'abonnement mensuel, même rattrapé à J-2 en février", () => {
      // Rattrapé le 26 février pour le 28, puis le 25 mars pour le 28 : 27 jours.
      const deliveries = [sent("2027-02-26", "2027-02-28")];
      expect(reminderOn({ renewsOn: "2027-03-28", deliveries }, "2027-03-25")).toBeDefined();
    });
  });

  it("ne vise qu'un abonnement App Store armé et daté, et passe à tous les rythmes", () => {
    expect(reminderOn({ renewsAtApple: false, renewsOn: null }, "2026-10-17")).toBeUndefined();
    expect(reminderOn({ renewsOn: null }, "2026-10-17")).toBeUndefined();
    // La question du rythme passée : le palier léger reçoit la facturation.
    expect(reminderOn({ trips: [trip({ narrationPace: null })] }, "2026-10-17")).toBeDefined();
  });
});

describe("l'e-mail de fin de voyage", () => {
  it("part le lendemain de la fin, entre 10 h et 21 h, une fois par voyage", () => {
    const camille = account(armed);

    expect(planTripEndEmail(camille, "2026-10-12", 10)).toBeNull();
    expect(planTripEndEmail(camille, "2026-10-13", 10)).toEqual({
      kind: "trip_end_email",
      dedupeKey: "camille:trip_end_email:rome",
      trip: camille.trips[0],
    });
    expect(planTripEndEmail(camille, "2026-10-13", 9)).toBeNull();
    expect(planTripEndEmail(camille, "2026-10-13", 21)).toBeNull();
  });

  it("rattrape une passe manquée jusqu'à J+3, pas au-delà", () => {
    expect(planTripEndEmail(account(armed), "2026-10-15", 12)?.trip.id).toBe("rome");
    expect(planTripEndEmail(account(armed), "2026-10-16", 12)).toBeNull();
  });

  it("ne vise qu'un abonnement App Store qui va se renouveler", () => {
    expect(planTripEndEmail(account(), "2026-10-13", 10)).toBeNull();
  });

  it("ne vise qu'un compte qui a une adresse", () => {
    expect(planTripEndEmail(account({ ...armed, hasEmail: false }), "2026-10-13", 10)).toBeNull();
  });

  it("se tait tant qu'un voyage court ou s'annonce : l'abonnement sert encore", () => {
    const next = account({ ...armed, trips: [trip(), trip({ id: "lisbonne", startsOn: "2026-11-02", endsOn: "2026-11-09" })] });
    expect(planTripEndEmail(next, "2026-10-13", 10)).toBeNull();

    const undated = (storedStage: PlannerTrip["storedStage"]) =>
      account({ ...armed, trips: [trip(), trip({ id: "sans-date", startsOn: null, endsOn: null, storedStage })] });
    expect(planTripEndEmail(undated("ongoing"), "2026-10-13", 10)).toBeNull();
    expect(planTripEndEmail(undated("past"), "2026-10-13", 10)?.trip.id).toBe("rome");
  });

  it("ne dépend pas des alertes du voyage : c'est la promesse du paywall, pas une relance", () => {
    const muted = account({ ...armed, trips: [trip({ notificationsEnabled: false, notifyTripEnd: false })] });
    expect(planTripEndEmail(muted, "2026-10-13", 10)?.trip.id).toBe("rome");
  });

  it("ne parle que du voyage fini le plus récemment, s'il y en a deux", () => {
    const two = account({ ...armed, trips: [trip({ id: "naples", endsOn: "2026-10-11" }), trip()] });
    expect(planTripEndEmail(two, "2026-10-13", 10)?.dedupeKey).toBe("camille:trip_end_email:rome");
  });
});

describe("la relance d'écriture", () => {
  it("part au rythme du récit choisi, le soir, trois fois au plus sur un même silence", () => {
    // Tous les 2 jours, dernier récit le 3 : relances le 5, le 7, le 9, puis plus rien.
    const camille = account();
    const on = (date: string) => planNotifications(camille, [], date).filter((n) => n.kind === "writing_reminder");

    expect(on("2026-10-04")).toHaveLength(0);
    expect(on("2026-10-05")[0]).toMatchObject({
      dedupeKey: "camille:writing_reminder:rome:2026-10-03:1",
      link: "memobook://trips/rome/chat",
      earliestHour: 19,
    });
    expect(on("2026-10-07")[0]?.dedupeKey).toBe("camille:writing_reminder:rome:2026-10-03:2");
    expect(on("2026-10-09")[0]?.dedupeKey).toBe("camille:writing_reminder:rome:2026-10-03:3");
    expect(on("2026-10-11")).toHaveLength(0);
  });

  it("reprend la relance écrite d'après le récit, quand il y en a une", () => {
    const camille = account({ trips: [trip({ prompt: "Comment ça se passe à Trastevere ?" })] });
    const due = planNotifications(camille, [], "2026-10-05").find((n) => n.kind === "writing_reminder");
    expect(due?.body).toBe("Comment ça se passe à Trastevere ?");
  });

  it("va chercher un carnet encore vide, à compter du départ", () => {
    const empty = account({ trips: [trip({ storyCount: 0, lastStoryOn: null })] });
    const due = planNotifications(empty, [], "2026-10-03").find((n) => n.kind === "writing_reminder");
    expect(due?.title).toBe("Ton carnet à Rome t’attend");
  });

  it("ne relance pas qui a passé la question du rythme (rythme léger)", () => {
    const silent = account({ trips: [trip({ narrationPace: null })] });
    expect(kinds(planNotifications(silent, [], "2026-10-09"))).not.toContain("writing_reminder");
  });

  it("étire le rythme de qui n'ouvre jamais ses notifications", () => {
    const ignoring: PlannerDelivery[] = [1, 2, 3, 4].map((n) => ({
      kind: "writing_reminder",
      dedupeKey: `old-${n}`,
      sentOn: "2026-09-01",
      opened: false,
    }));
    // Tous les jours, mais rien n'est jamais ouvert : tous les deux jours.
    const camille = account({ deliveries: ignoring, trips: [trip({ narrationPace: "daily" })] });
    expect(kinds(planNotifications(camille, [], "2026-10-04"))).not.toContain("writing_reminder");
    expect(kinds(planNotifications(camille, [], "2026-10-05"))).toContain("writing_reminder");
  });

  it("relance moins le rythme modéré — une fois par silence, à l'intervalle choisi", () => {
    // Une fois par semaine, dernier récit le 3 : une relance le 10, et c'est tout.
    const camille = account({ trips: [trip({ narrationPace: "weekly", endsOn: "2026-10-31" })] });
    const on = (date: string) => planNotifications(camille, [], date).filter((n) => n.kind === "writing_reminder");

    expect(on("2026-10-09")).toHaveLength(0);
    expect(on("2026-10-10")[0]?.dedupeKey).toBe("camille:writing_reminder:rome:2026-10-03:1");
    expect(on("2026-10-17")).toHaveLength(0);
  });

  it("respecte l'alerte « Rappel d'écriture » du voyage", () => {
    const off = account({ trips: [trip({ notifyWritingReminder: false })] });
    expect(kinds(planNotifications(off, [], "2026-10-05"))).not.toContain("writing_reminder");
  });
});

describe("le carnet terminé mais pas commandé", () => {
  const ended = trip({ narrationPace: "daily", lastStoryOn: "2026-10-11" });

  it("relance le propriétaire trois jours après la fin, puis dix", () => {
    const camille = account({ usedRecently: true, trips: [ended] });
    expect(kinds(planNotifications(camille, [], "2026-10-14"))).not.toContain("unordered_book");
    expect(planNotifications(camille, [], "2026-10-15").find((n) => n.kind === "unordered_book")?.dedupeKey).toBe(
      "camille:unordered_book:rome:3",
    );
    expect(planNotifications(camille, [], "2026-10-22").find((n) => n.kind === "unordered_book")?.dedupeKey).toBe(
      "camille:unordered_book:rome:10",
    );
    expect(kinds(planNotifications(camille, [], "2026-10-29"))).not.toContain("unordered_book");
  });

  it("ne relance ni un carnet commandé, ni un co-voyageur", () => {
    expect(
      kinds(planNotifications(account({ trips: [{ ...ended, hasOrder: true }] }), [], "2026-10-15")),
    ).not.toContain("unordered_book");
    expect(
      kinds(planNotifications(account({ trips: [{ ...ended, isOwner: false }] }), [], "2026-10-15")),
    ).not.toContain("unordered_book");
  });
});

describe("les vacances scolaires", () => {
  const sustained = { trips: [trip({ narrationPace: "daily", startsOn: "2026-06-01", endsOn: "2026-06-10" })] };
  const holidayOn = (who: PlannerAccount, holidays: SchoolHolidayPeriod[], date: string) =>
    planNotifications(who, holidays, date).find((n) => n.kind === "school_holidays");

  it("partent à J-7 et le jour J, dans la zone du voyageur — plus à J-3", () => {
    const camille = account({ ...sustained, schoolCalendar: "B" });
    for (const [date, label] of [
      ["2026-10-10", "J-7"],
      ["2026-10-17", "J-0"],
    ] as const) {
      const due = holidayOn(camille, [toussaintB], date);
      expect(due?.dedupeKey).toBe(`camille:school_holidays:2026-2027:Vacances de la Toussaint:${label}`);
      expect(due?.link).toBe("memobook://trips/new");
    }
    expect(holidayOn(camille, [toussaintB], "2026-10-14")).toBeUndefined();
    expect(holidayOn(camille, [toussaintB], "2026-10-10")?.title).toBe("Vacances de la Toussaint dans une semaine");
  });

  it("sans code postal, suivent les premières vacances de chaque période", () => {
    const camille = account({ ...sustained, schoolCalendar: "earliest" });
    // L'hiver de la zone B, la première partie : J-7 le 30 janvier.
    expect(holidayOn(camille, winter, "2027-01-30")?.dedupeKey).toBe(
      "camille:school_holidays:2026-2027:Vacances d'Hiver:J-7",
    );
    expect(holidayOn(camille, winter, "2027-02-06")?.title).toBe("C’est le début des vacances d’hiver !");
    // Ni la zone A, ni la zone C ne parlent une seconde fois.
    expect(holidayOn(camille, winter, "2027-02-13")).toBeUndefined();
    expect(holidayOn(camille, winter, "2027-02-20")).toBeUndefined();
  });

  it("ne partent pas hors calendrier, dans une autre zone, ou au rythme modéré", () => {
    expect(kinds(planNotifications(account(sustained), [toussaintB], "2026-10-10"))).not.toContain("school_holidays");
    expect(holidayOn(account({ ...sustained, schoolCalendar: "A" }), [toussaintB], "2026-10-10")).toBeUndefined();
    const moderate = account({
      schoolCalendar: "B",
      trips: [trip({ narrationPace: "weekly", endsOn: "2026-06-10" })],
    });
    expect(holidayOn(moderate, [toussaintB], "2026-10-10")).toBeUndefined();
  });

  it("ne suggèrent pas un voyage à qui en a déjà un pendant ces vacances", () => {
    const camille = account({
      schoolCalendar: "B",
      trips: [...sustained.trips, trip({ id: "lisbonne", startsOn: "2026-10-20", endsOn: "2026-10-25" })],
    });
    expect(kinds(planNotifications(camille, [toussaintB], "2026-10-10"))).not.toContain("school_holidays");
  });
});

describe("le nouveau récit d'un co-voyageur", () => {
  const news = { names: ["Clara"], stories: 2, photos: 0, latestMessageId: "msg-9" };

  it("annonce ce qu'un co-voyageur a raconté, vers le fil, avec la bulle de MEMO qui le reprend", () => {
    const camille = account({ trips: [trip({ narrationPace: "daily", memberCount: 2, newFromOthers: news })] });
    const due = planNotifications(camille, [], "2026-10-04").find((n) => n.kind === "new_story");

    expect(due).toMatchObject({
      dedupeKey: "camille:new_story:rome:msg-9",
      link: "memobook://trips/rome/chat",
      memoId: "rome",
      title: "Nouveau récit à Rome",
      body: "Clara a ajouté 2 souvenirs au carnet. Viens voir, et raconte la suite à ton tour.",
    });
    // Une clé sans le compte, une par jour : le fil est commun, la bulle ne s'y écrit qu'une fois.
    expect(due?.chat).toEqual({
      key: "new_story:rome:2026-10-04",
      text: "Nouveau récit dans le carnet : Clara a ajouté 2 souvenirs. Qui raconte la suite ?",
    });
  });

  it("dit les photos et les auteurs, accordés", () => {
    const camille = account({
      trips: [
        trip({
          narrationPace: "daily",
          newFromOthers: { names: ["Clara", "Paul"], stories: 1, photos: 3, latestMessageId: "m" },
        }),
      ],
    });
    expect(planNotifications(camille, [], "2026-10-04").find((n) => n.kind === "new_story")?.body).toBe(
      "Clara et Paul ont ajouté un souvenir et 3 photos au carnet. Viens voir, et raconte la suite à ton tour.",
    );
  });

  it("se tait au rythme modéré, ou si l'alerte « Nouveau récit » est coupée", () => {
    const moderate = account({ trips: [trip({ narrationPace: "weekly", newFromOthers: news })] });
    expect(kinds(planNotifications(moderate, [], "2026-10-04"))).not.toContain("new_story");
    const off = account({ trips: [trip({ narrationPace: "daily", newFromOthers: news, notifyNewStory: false })] });
    expect(kinds(planNotifications(off, [], "2026-10-04"))).not.toContain("new_story");
  });
});

describe("le résumé de la semaine", () => {
  // Départ le 1er octobre : le point tombe le 8, le 15…, dans une fenêtre de trois jours.
  const busy = { weekStories: 5, weekPhotos: 12 };

  it("fait le point tous les sept jours, le soir, vers le fil, avec sa bulle", () => {
    const camille = account({ trips: [trip({ ...busy, endsOn: "2026-10-31" })] });
    const on = (date: string) => planNotifications(camille, [], date).find((n) => n.kind === "weekly_digest");

    expect(on("2026-10-07")).toBeUndefined();
    expect(on("2026-10-08")).toMatchObject({
      dedupeKey: "camille:weekly_digest:rome:week-1",
      link: "memobook://trips/rome/chat",
      earliestHour: 18,
      title: "Le point de la semaine à Rome",
      body: "5 souvenirs et 12 photos capturés cette semaine. Ton carnet prend forme : viens voir où il en est.",
      chat: {
        key: "weekly_digest:rome:week-1",
        text: "Le point de la semaine : 5 souvenirs et 12 photos capturés cette semaine. Le carnet prend forme ! On continue ?",
      },
    });
    expect(on("2026-10-10")?.dedupeKey).toBe("camille:weekly_digest:rome:week-1");
    expect(on("2026-10-11")).toBeUndefined();
    expect(on("2026-10-15")?.dedupeKey).toBe("camille:weekly_digest:rome:week-2");
  });

  it("dit « votre » carnet à plusieurs, et part aussi au rythme modéré", () => {
    const shared = account({
      trips: [trip({ ...busy, narrationPace: "weekly", memberCount: 3, endsOn: "2026-10-31" })],
    });
    expect(planNotifications(shared, [], "2026-10-08").find((n) => n.kind === "weekly_digest")?.body).toContain(
      "Votre carnet prend forme",
    );
  });

  it("se tait pour une semaine sans souvenir, un voyage fini, ou l'alerte coupée", () => {
    const on = (overrides: Partial<PlannerTrip>, date = "2026-10-08") =>
      kinds(planNotifications(account({ trips: [trip({ ...busy, endsOn: "2026-10-31", ...overrides })] }), [], date));
    expect(on({ weekStories: 0, weekPhotos: 0 })).not.toContain("weekly_digest");
    expect(on({ endsOn: "2026-10-06" })).not.toContain("weekly_digest");
    expect(on({ notifyWeeklyDigest: false })).not.toContain("weekly_digest");
    expect(on({ weekStories: 1, weekPhotos: 0 })).toContain("weekly_digest");
  });
});

describe("le comportement appris", () => {
  it("rappelle, quinze jours avant, la période où le voyageur est parti l'an dernier — un voyage suffit", () => {
    const camille = account({
      usedRecently: true,
      trips: [trip({ id: "porto", city: "Porto", startsOn: "2025-11-01", endsOn: "2025-11-08", narrationPace: "daily" })],
    });
    const due = planNotifications(camille, [], "2026-10-18").find((n) => n.kind === "learned_period");
    expect(due?.title).toBe("L’an dernier à la même époque, tu partais à Porto");
    expect(due?.dedupeKey).toBe("camille:learned_period:2026-11-01");
  });

  it("passe d'une année à l'autre : un voyage du 5 janvier se rappelle en décembre", () => {
    const camille = account({
      trips: [trip({ startsOn: "2026-01-05", endsOn: "2026-01-12", narrationPace: "daily" })],
    });
    expect(kinds(planNotifications(camille, [], "2026-12-22"))).toContain("learned_period");
  });
});

describe("l'anniversaire", () => {
  const sustained = { trips: [trip({ narrationPace: "daily", startsOn: "2026-06-01", endsOn: "2026-06-10" })] };

  it("part une semaine avant", () => {
    const camille = account({ ...sustained, birthDate: "1994-10-28" });
    expect(planNotifications(camille, [], "2026-10-21").find((n) => n.kind === "birthday")?.dedupeKey).toBe(
      "camille:birthday:2026",
    );
  });

  it("ne se cumule pas avec un voyage en cours", () => {
    const travelling = account({
      birthDate: "1994-10-28",
      trips: [trip({ narrationPace: "daily", startsOn: "2026-10-15", endsOn: "2026-10-25" })],
    });
    expect(kinds(planNotifications(travelling, [], "2026-10-21"))).not.toContain("birthday");
  });
});

describe("les règles anti-saturation", () => {
  const candidate = (kind: PlannedNotification["kind"], priority: number, family: PlannedNotification["family"]) =>
    ({
      kind,
      family,
      priority,
      dedupeKey: `k-${kind}`,
      earliestHour: 10,
      memoId: null,
      link: "memobook://trips/new",
      title: kind,
      body: kind,
    }) satisfies PlannedNotification;

  const birthday = candidate("birthday", 20, "holiday");
  const school = candidate("school_holidays", 12, "holiday");
  const tripEnd = candidate("trip_end", 100, "billing");

  it("n'envoie qu'une notification de vacances quand deux tombent le même jour — la plus pertinente", () => {
    expect(kinds(selectNotifications([school, birthday], [], "2026-10-21", 10))).toEqual(["birthday"]);
  });

  it("fait passer la facturation, seule, un jour où elle parle", () => {
    expect(kinds(selectNotifications([birthday, tripEnd], [], "2026-10-21", 10))).toEqual(["trip_end"]);
    const billedThisMorning: PlannerDelivery[] = [
      { kind: "renewal_reminder", dedupeKey: "x", sentOn: "2026-10-21", opened: false },
    ];
    expect(selectNotifications([birthday], billedThisMorning, "2026-10-21", 15)).toEqual([]);
  });

  it("laisse partir ensemble deux notifications de facturation du même jour", () => {
    const reminder = candidate("renewal_reminder", 90, "billing");
    expect(kinds(selectNotifications([birthday, reminder, tripEnd], [], "2026-10-21", 10))).toEqual([
      "renewal_reminder",
      "trip_end",
    ]);
  });

  it("ne laisse partir qu'une notification de vacances par semaine glissante", () => {
    const sixDaysAgo: PlannerDelivery[] = [
      { kind: "school_holidays", dedupeKey: "j7", sentOn: "2026-10-10", opened: true },
    ];
    expect(selectNotifications([school], sixDaysAgo, "2026-10-16", 10)).toEqual([]);
    expect(kinds(selectNotifications([school], sixDaysAgo, "2026-10-17", 10))).toEqual(["school_holidays"]);
  });

  it("une par jour hors facturation, rien avant l'heure, rien après 21 h, rien deux fois", () => {
    const reminder = { ...candidate("writing_reminder", 50, "engagement"), earliestHour: 19 };
    expect(selectNotifications([reminder], [], "2026-10-21", 18)).toEqual([]);
    expect(kinds(selectNotifications([reminder], [], "2026-10-21", 19))).toEqual(["writing_reminder"]);
    expect(selectNotifications([reminder], [], "2026-10-21", 21)).toEqual([]);

    const sentThisMorning: PlannerDelivery[] = [
      { kind: "birthday", dedupeKey: "k-birthday", sentOn: "2026-10-21", opened: false },
    ];
    expect(selectNotifications([reminder], sentThisMorning, "2026-10-21", 19)).toEqual([]);
    expect(selectNotifications([birthday], sentThisMorning, "2026-10-22", 10)).toEqual([]);
  });
});
