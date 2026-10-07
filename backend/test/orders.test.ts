import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Le tunnel de commande, côté serveur : ce que l'app reçoit pour l'ouvrir, ce
 * que le récapitulatif compte, et ce que la commande retient.
 */
/**
 * Ce que les tests lisent des réponses. Volontairement **partiels** : un type
 * complet ici serait une troisième description du contrat, à tenir d'accord
 * avec le sérialiseur et avec les modèles Swift.
 */
type ContextBody = {
  bookTitle: string;
  wallet: {
    tripId: string | null;
    balance: number;
    entries: unknown[];
    tripTitle: string | null;
    estimate: unknown;
  };
  shipping: Record<string, unknown> & { country: string };
  countries: { code: string }[];
  options: Record<string, unknown>;
  standardDays: Record<string, unknown>;
  phoneNumber: string | null;
};

type QuoteBody = {
  book: { lines: { label: string; amount: number }[]; subtotal: number };
  specifications: string[];
  fulfilment: { subtotal: number };
  deductions: { id: string; label: string; amount: number }[];
  total: number;
};

type OrderBody = {
  id: string;
  status: string;
  total: number;
  copyOptions: { position: number }[];
  notifyByWhatsApp: boolean;
  whatsappPhone: string | null;
};

type ProfileBody = {
  orders: { id: string; status: string; memoId: string; tripTitle: string | null; total: number | null }[];
};

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

/** Un carnet composé, donc commandable. */
async function printableTrip(accountId: string) {
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Lisbonne entre filles",
      bookTitle: "Lisbonne, plein sud",
      accessCode: `ORD${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
      stage: "past",
      pageCount: 58,
      targetPageCount: 60,
      isPrintable: true,
      renders: { create: [{ status: "ready", pdfUrl: "https://pdf.example.test/l.pdf" }] },
    },
    include: { renders: true },
  });
  return { memo, renderId: memo.renders[0]!.id };
}

const shipping = {
  name: "Hugo Jouffre",
  line1: "7 rue Simon Fryd",
  postalCode: "69002",
  city: "Lyon",
  country: "FR",
};

describe("ce que le tunnel reçoit pour s'ouvrir", () => {
  /**
   * **La régression qui a blanchi l'étape 1.** `OrderContext.wallet` est un
   * ``Wallet`` Swift, dont `entries` n'est pas optionnel : un objet partiel
   * faisait échouer le décodage de *tout* l'écran, pas seulement de la ligne
   * concernée. La cagnotte est retirée (06/10/2026), mais les builds installés
   * le décodent encore : il reste complet, **gelé à zéro**.
   */
  it("rend une cagnotte gelée mais complète, pour les builds installés", async () => {
    const account = await registerAccount(harness.app);
    const { memo } = await printableTrip(account.accountId);

    const response = await harness.app.inject({
      method: "GET",
      url: `/v1/memos/${memo.id}/order-context`,
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(200);
    const body = response.json<ContextBody>();
    expect(Object.keys(body.wallet).sort()).toEqual(
      ["balance", "entries", "estimate", "tripId", "tripTitle"].sort(),
    );
    expect(body.wallet.tripId).toBe(memo.id);
    expect(body.wallet.entries).toEqual([]);
    expect(body.wallet.balance).toBe(0);
  });

  it("rend le solde à zéro même quand l'ancien registre en porte un", async () => {
    const account = await registerAccount(harness.app);
    const { memo } = await printableTrip(account.accountId);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { walletBalanceCents: 2_500 },
    });

    const body = (
      await harness.app.inject({
        method: "GET",
        url: `/v1/memos/${memo.id}/order-context`,
        headers: { authorization: account.authorization },
      })
    ).json<ContextBody>();

    expect(body.wallet.balance).toBe(0);
    expect(body.wallet.entries).toEqual([]);
  });

  /**
   * **Le contrat, champ par champ.**
   *
   * Swift décode `OrderContext` d'un bloc : un seul champ non optionnel absent
   * et l'écran entier reste en squelette, sur une erreur qui ne nomme que la
   * clé manquante. Ça s'est produit deux fois de suite — `wallet.entries`, puis
   * `options.position`. Ce test liste ce que les modèles exigent, pour que la
   * troisième fois soit rouge ici plutôt que grise dans le simulateur.
   */
  it("porte tous les champs que les modèles Swift exigent", async () => {
    const account = await registerAccount(harness.app);
    const { memo } = await printableTrip(account.accountId);

    const body = (
      await harness.app.inject({
        method: "GET",
        url: `/v1/memos/${memo.id}/order-context`,
        headers: { authorization: account.authorization },
      })
    ).json<ContextBody>();

    for (const key of [
      "memoId",
      "renderId",
      "bookTitle",
      "pageCount",
      "trip",
      "wallet",
      "unitPrice",
      "expressPrice",
      "standardDays",
      "expressDays",
      "shipping",
      "countries",
      "cards",
      "selectedCardId",
      "phoneNumber",
      "options",
    ]) {
      expect(body, `OrderContext.${key}`).toHaveProperty(key);
    }

    // `PrintedCopyOptions` porte toujours un rang.
    expect(Object.keys(body.options).sort()).toEqual(
      [
        "position",
        "decorationsEnabled",
        "quizEnabled",
        "freeZonesEnabled",
        "crosswordEnabled",
      ].sort(),
    );

    // `DayRange` : deux bornes, jamais une date.
    expect(Object.keys(body.standardDays).sort()).toEqual(["max", "min"]);

    // `ShippingAddress` : la deuxième ligne est optionnelle, les autres non.
    for (const key of ["name", "line1", "postalCode", "city", "country"]) {
      expect(body.shipping, `ShippingAddress.${key}`).toHaveProperty(key);
    }
  });

  it("propose l'adresse du compte et un pays livrable", async () => {
    const account = await registerAccount(harness.app);
    const { memo } = await printableTrip(account.accountId);

    const body = (
      await harness.app.inject({
        method: "GET",
        url: `/v1/memos/${memo.id}/order-context`,
        headers: { authorization: account.authorization },
      })
    ).json<ContextBody>();

    expect(body.shipping.country).toBe("FR");
    expect(body.countries.some((c) => c.code === "FR")).toBe(true);
    // Le titre du **récit**, pas le nom du voyage.
    expect(body.bookTitle).toBe("Lisbonne, plein sud");
  });
});

describe("le récapitulatif", () => {
  it("ne facture qu'une ligne, et décrit le reste", async () => {
    const account = await registerAccount(harness.app);
    const { memo } = await printableTrip(account.accountId);

    const quote = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders/quote`,
        headers: { authorization: account.authorization },
        payload: { copies: 2, shippingSpeed: "express" },
      })
    ).json<QuoteBody>();

    // Une seule ligne facturée : le prix ne dépend que des pages.
    expect(quote.book.lines).toHaveLength(1);
    expect(quote.book.lines[0]?.label).toContain("pages");
    // Le papier, la couverture et la reliure **décrivent**, ils ne facturent pas.
    expect(quote.specifications).toContain("80g. non couché ivoire");
    expect(quote.total).toBe(quote.fulfilment.subtotal);
  });

  it("ne déduit plus rien : la cagnotte est retirée (06/10/2026)", async () => {
    const account = await registerAccount(harness.app);
    const { memo } = await printableTrip(account.accountId);
    // Un ancien solde, d'avant le retrait : il ne se déduit plus.
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { walletBalanceCents: 2_500 },
    });

    const quote = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders/quote`,
        headers: { authorization: account.authorization },
        payload: { copies: 1, shippingSpeed: "standard" },
      })
    ).json<QuoteBody>();

    expect(quote.deductions).toEqual([]);
    expect(quote.total).toBe(quote.fulfilment.subtotal);
  });
});

describe("la commande", () => {
  it("recalcule son prix, quoi qu'en dise l'app", async () => {
    const account = await registerAccount(harness.app);
    const { memo, renderId } = await printableTrip(account.accountId);

    const order = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders`,
        headers: { authorization: account.authorization },
        payload: { renderId, copies: 2, shippingSpeed: "express", shipping },
      })
    ).json<OrderBody>();

    const quote = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders/quote`,
        headers: { authorization: account.authorization },
        payload: { copies: 2, shippingSpeed: "express" },
      })
    ).json<QuoteBody>();

    expect(order.total).toBe(quote.total);
    // Un jeu d'options par exemplaire, même sans rien envoyer.
    expect(order.copyOptions.map((c) => c.position)).toEqual([1, 2]);
  });

  it("refuse un pays où l'imprimeur ne livre pas", async () => {
    const account = await registerAccount(harness.app);
    const { memo, renderId } = await printableTrip(account.accountId);

    const refused = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/orders`,
      headers: { authorization: account.authorization },
      payload: { renderId, copies: 1, shipping: { ...shipping, country: "ZZ" } },
    });

    expect(refused.statusCode).toBe(400);
  });

  /**
   * Le suivi du profil filtre sur **l'acheteur** et accepte les brouillons :
   * sans ça, la seule commande que l'app sache créer n'apparaissait nulle part.
   */
  it("se montre « paiement abandonné » tant qu'elle n'est pas payée (T232)", async () => {
    // Un brouillon est une commande **pas payée** : elle s'affichait « en
    // cours d'acheminement », avec ses jours de livraison. Puis elle a
    // disparu du suivi ; Hugo veut qu'elle y soit, étiquetée, avec de quoi la
    // finaliser (06/10/2026).
    const account = await registerAccount(harness.app);
    const { memo, renderId } = await printableTrip(account.accountId);

    const order = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders`,
        headers: { authorization: account.authorization },
        payload: { renderId, copies: 1, shipping },
      })
    ).json<OrderBody>();

    expect(order.status).toBe("draft");

    const tracked = async () =>
      (
        await harness.app.inject({
          method: "GET",
          url: "/v1/profile",
          headers: { authorization: account.authorization },
        })
      )
        .json<ProfileBody>().orders;

    expect(await tracked()).toEqual([
      expect.objectContaining({
        id: order.id,
        status: "payment_abandoned",
        memoId: memo.id,
        tripTitle: "Lisbonne entre filles",
        total: order.total,
      }),
    ]);

    // Fermée par le ménage, elle y reste : elle se finalise encore.
    await harness.prisma.printOrder.update({ where: { id: order.id }, data: { status: "cancelled" } });
    expect((await tracked()).map((o) => [o.id, o.status])).toEqual([[order.id, "payment_abandoned"]]);

    await harness.prisma.printOrder.update({
      where: { id: order.id },
      data: { status: "submitted", submittedAt: new Date() },
    });
    expect((await tracked()).map((o) => [o.id, o.status])).toEqual([[order.id, "in_progress"]]);

    // Payée puis remboursée : ni en route, ni abandonnée.
    await harness.prisma.printOrder.update({ where: { id: order.id }, data: { status: "cancelled" } });
    expect(await tracked()).toEqual([]);
  });

  it("ne montre que la dernière tentative d'un voyage, et plus rien une fois payée", async () => {
    const account = await registerAccount(harness.app);
    const { memo, renderId } = await printableTrip(account.accountId);
    const place = async () =>
      (
        await harness.app.inject({
          method: "POST",
          url: `/v1/memos/${memo.id}/orders`,
          headers: { authorization: account.authorization },
          payload: { renderId, copies: 1, shipping },
        })
      ).json<OrderBody>();
    const tracked = async () =>
      (
        await harness.app.inject({ method: "GET", url: "/v1/profile", headers: { authorization: account.authorization } })
      ).json<ProfileBody>().orders;

    // Une adresse changée au milieu du tunnel : la première est remplacée.
    const first = await place();
    await harness.app.inject({
      method: "POST",
      url: `/v1/orders/${first.id}/cancel`,
      headers: { authorization: account.authorization },
    });
    const second = await place();
    expect((await tracked()).map((o) => o.id)).toEqual([second.id]);

    // Une troisième, payée : plus rien d'abandonné sur ce voyage.
    const third = await place();
    await harness.prisma.printOrder.update({
      where: { id: third.id },
      data: { status: "submitted", submittedAt: new Date() },
    });
    expect((await tracked()).map((o) => [o.id, o.status])).toEqual([[third.id, "in_progress"]]);
  });
});

describe("le suivi par WhatsApp", () => {
  it("retient le numéro, et le pose sur le compte qui n'en a pas", async () => {
    const account = await registerAccount(harness.app);
    const { memo, renderId } = await printableTrip(account.accountId);

    const order = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders`,
        headers: { authorization: account.authorization },
        payload: { renderId, copies: 1, shipping },
      })
    ).json<OrderBody>();

    const updated = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/orders/${order.id}/whatsapp`,
        headers: { authorization: account.authorization },
        payload: { enabled: true, phone: "+33 6 11 22 33 44" },
      })
    ).json<OrderBody>();

    expect(updated.notifyByWhatsApp).toBe(true);
    expect(updated.whatsappPhone).toBe("+33 6 11 22 33 44");

    const saved = await harness.prisma.account.findUniqueOrThrow({
      where: { id: account.accountId },
      select: { phoneNumber: true },
    });
    expect(saved.phoneNumber).toBe("+33 6 11 22 33 44");
  });

  /** Un accord sans destinataire serait une promesse que personne ne tient. */
  it("refuse l'accord sans numéro", async () => {
    const account = await registerAccount(harness.app);
    const { memo, renderId } = await printableTrip(account.accountId);

    const order = (
      await harness.app.inject({
        method: "POST",
        url: `/v1/memos/${memo.id}/orders`,
        headers: { authorization: account.authorization },
        payload: { renderId, copies: 1, shipping },
      })
    ).json<OrderBody>();

    const refused = await harness.app.inject({
      method: "POST",
      url: `/v1/orders/${order.id}/whatsapp`,
      headers: { authorization: account.authorization },
      payload: { enabled: true },
    });

    expect(refused.statusCode).toBe(400);
  });
});
