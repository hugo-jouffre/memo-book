import { describe, expect, it } from "vitest";
import {
  planNotifications,
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
    notifyTripEnd: true,
    prompt: null,
    storyCount: 2,
    lastStoryOn: "2026-10-03",
    isOwner: true,
    hasOrder: false,
    paidCents: 0,
    estimateCents: 4290,
    ...overrides,
  };
}

function account(overrides: Partial<PlannerAccount> = {}): PlannerAccount {
  return {
    id: "camille",
    birthDate: null,
    schoolZone: null,
    remainingSteps: 3,
    isSubscribed: false,
    renewsAtApple: false,
    stopsAutomatically: false,
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

describe("la fin des 3 jours offerts", () => {
  it("part à J+3 du premier voyage, une fois", () => {
    const camille = account({ trips: [trip({ createdOn: "2026-10-01", lastStoryOn: "2026-10-04" })] });

    expect(kinds(planNotifications(camille, [], "2026-10-03"))).not.toContain("trial_end");
    const due = planNotifications(camille, [], "2026-10-04").find((n) => n.kind === "trial_end");
    expect(due).toMatchObject({ dedupeKey: "camille:trial_end:once", link: "memobook://paywall" });
    expect(due?.body).toContain("1,99");
    expect(due?.body).toContain("déduite du prix de ton carnet");
    expect(kinds(planNotifications(camille, [], "2026-10-05"))).not.toContain("trial_end");
  });

  it("ne part ni pour un abonné, ni pour un compte sans quota", () => {
    const base = { trips: [trip({ createdOn: "2026-10-01" })] };
    expect(kinds(planNotifications(account({ ...base, isSubscribed: true }), [], "2026-10-04"))).not.toContain(
      "trial_end",
    );
    expect(kinds(planNotifications(account({ ...base, remainingSteps: null }), [], "2026-10-04"))).not.toContain(
      "trial_end",
    );
  });

  it("se compte depuis un voyage qu'on possède, pas depuis un voyage rejoint", () => {
    const joined = account({ trips: [trip({ createdOn: "2026-10-01", isOwner: false })] });
    expect(kinds(planNotifications(joined, [], "2026-10-04"))).not.toContain("trial_end");
  });
});

describe("la fin du voyage", () => {
  it("part le jour de la date de fin, vers la cagnotte du voyage, avec ce qui est déjà versé", () => {
    const camille = account({ stopsAutomatically: true, trips: [trip({ paidCents: 597 })] });
    const due = planNotifications(camille, [], "2026-10-12").find((n) => n.kind === "trip_end");

    expect(due).toMatchObject({ link: "memobook://trips/rome/wallet", memoId: "rome", family: "billing" });
    expect(due?.title).toBe("Ton voyage à Rome se termine aujourd’hui");
    expect(due?.body).toContain("Ton abonnement s’arrête automatiquement.");
    expect(due?.body).toMatch(/Tu as déjà versé 5,97\s€, déduits de ton carnet estimé à 42,90\s€/);
  });

  it("n'écrit pas « arrêté automatiquement » à un abonné App Store : il l'invite à le couper", () => {
    const due = planNotifications(account({ renewsAtApple: true }), [], "2026-10-12").find(
      (n) => n.kind === "trip_end",
    );
    expect(due?.body).not.toContain("automatiquement");
    expect(due?.body).toContain("coupe-le en un geste");
  });

  it("ne parle pas de l'abonnement quand un autre voyage le fait encore courir", () => {
    const camille = account({
      stopsAutomatically: true,
      trips: [trip(), trip({ id: "lisbonne", startsOn: "2026-11-02", endsOn: "2026-11-09" })],
    });
    const due = planNotifications(camille, [], "2026-10-12").find((n) => n.kind === "trip_end");
    expect(due?.body).not.toContain("abonnement");
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

  it("partent à J-7, J-3 et le jour J, dans la zone du voyageur", () => {
    const camille = account({ ...sustained, schoolZone: "B" });
    for (const [date, label] of [
      ["2026-10-10", "J-7"],
      ["2026-10-14", "J-3"],
      ["2026-10-17", "J-0"],
    ] as const) {
      const due = planNotifications(camille, [toussaintB], date).find((n) => n.kind === "school_holidays");
      expect(due?.dedupeKey).toBe(`camille:school_holidays:B:2026-2027:Vacances de la Toussaint:${label}`);
      expect(due?.link).toBe("memobook://trips/new");
    }
    expect(
      planNotifications(camille, [toussaintB], "2026-10-10").find((n) => n.kind === "school_holidays")?.title,
    ).toBe("Vacances de la Toussaint dans une semaine");
  });

  it("ne partent pas sans zone, dans une autre zone, ou au rythme modéré", () => {
    expect(kinds(planNotifications(account(sustained), [toussaintB], "2026-10-10"))).not.toContain("school_holidays");
    expect(
      kinds(planNotifications(account({ ...sustained, schoolZone: "A" }), [toussaintB], "2026-10-10")),
    ).not.toContain("school_holidays");
    const moderate = account({ schoolZone: "B", trips: [trip({ narrationPace: "weekly", endsOn: "2026-06-10" })] });
    expect(kinds(planNotifications(moderate, [toussaintB], "2026-10-10"))).not.toContain("school_holidays");
  });

  it("ne suggèrent pas un voyage à qui en a déjà un pendant ces vacances", () => {
    const camille = account({
      schoolZone: "B",
      trips: [...sustained.trips, trip({ id: "lisbonne", startsOn: "2026-10-20", endsOn: "2026-10-25" })],
    });
    expect(kinds(planNotifications(camille, [toussaintB], "2026-10-10"))).not.toContain("school_holidays");
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
      { kind: "trial_end", dedupeKey: "x", sentOn: "2026-10-21", opened: false },
    ];
    expect(selectNotifications([birthday], billedThisMorning, "2026-10-21", 15)).toEqual([]);
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
