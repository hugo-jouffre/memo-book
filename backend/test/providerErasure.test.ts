import Stripe from "stripe";
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";
import { eraseTrace } from "../src/jobs/eraseTrace.js";
import { JOB_NAMES, PgBossQueue } from "../src/jobs/queue.js";
import { ApiTemplateRenderer, FAKE_PDF_BASE_URL } from "../src/services/apitemplate.js";
import { StripePaymentGateway } from "../src/services/payments.js";
import type { InMemoryMediaStorage } from "../src/services/storage.js";
import { WebflowAssetPublisher } from "../src/services/webflow.js";

/**
 * **Ce qui reste chez les prestataires quand on supprime** (23/10/2026) : le
 * client Stripe d'un compte, les copies Webflow de ses photos, les PDF de ses
 * carnets chez APITemplate. Nos tables les oubliaient avec le reste ; ces
 * copies-là survivaient au compte.
 *
 * La file est en ligne dans les tests : publier une trace l'efface aussitôt.
 * Ce qui est vérifié ici, c'est **qui** est effacé — et surtout qui ne l'est
 * pas : ce qui a changé de main reste à l'héritier.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

afterAll(async () => {
  await harness?.close();
});

let accessCodeCounter = 0;

async function seedTrip(accountId: string) {
  accessCodeCounter += 1;
  return harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      accessCode: `EFF${String(accessCodeCounter).padStart(3, "0")}`,
    },
  });
}

/** Une photo publiée sur le CDN, et le carnet composé qui l'a utilisée. */
async function seedPublishedBook(memoId: string, tag: string) {
  const media = await harness.prisma.mediaAsset.create({
    data: {
      storageKey: `photos/${tag}.jpg`,
      mimeType: "image/jpeg",
      bytes: 12,
      cdnUrl: `https://cdn.prod.website-files.com/site/${tag}.jpg`,
      cdnAssetId: `wf_${tag}`,
    },
  });
  const entry = await harness.prisma.entry.create({
    data: { memoId, kind: "photo", status: "ready", mediaId: media.id },
  });
  await harness.prisma.render.create({
    data: {
      memoId,
      status: "ready",
      apitemplateTransactionId: `tx_${tag}`,
      pdfUrl: `https://s3.eu-central-1.amazonaws.com/apitemplate/${tag}.pdf`,
    },
  });
  return { media, entry };
}

function spyOnProviders() {
  return {
    stripe: vi.spyOn(harness.context.payments, "deleteCustomer"),
    webflow: vi.spyOn(harness.context.publisher, "unpublish"),
    apitemplate: vi.spyOn(harness.context.renderer, "discard"),
  };
}

describe("la suppression d'un compte, chez les prestataires", () => {
  it("efface son client Stripe, ses photos publiées et ses PDF", async () => {
    const account = await registerAccount(harness.app);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { stripeCustomerId: "cus_partant" },
    });
    const memo = await seedTrip(account.accountId);
    await seedPublishedBook(memo.id, "solo");
    // Un rendu du simulé : son identifiant n'existe chez personne.
    await harness.prisma.render.create({
      data: {
        memoId: memo.id,
        status: "ready",
        apitemplateTransactionId: "0123456789abcdef01234567",
        pdfUrl: `${FAKE_PDF_BASE_URL}0123456789abcdef01234567.pdf`,
      },
    });
    const spies = spyOnProviders();

    const response = await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(204);
    expect(spies.stripe.mock.calls).toEqual([["cus_partant"]]);
    expect(spies.webflow.mock.calls).toEqual([["wf_solo"]]);
    expect(spies.apitemplate.mock.calls).toEqual([["tx_solo"]]);
  });

  it("laisse au co-voyageur les photos et le PDF du voyage dont il hérite", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const heir = await registerAccount(harness.app, "heritier@memobook.app");
    const shared = await seedTrip(owner.accountId);
    await harness.prisma.memoMember.create({
      data: { memoId: shared.id, accountId: heir.accountId, status: "active", acceptedAt: new Date() },
    });
    await seedPublishedBook(shared.id, "partage");
    const spies = spyOnProviders();

    await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: owner.authorization },
    });

    expect(await harness.prisma.memo.count({ where: { ownerAccountId: heir.accountId } })).toBe(1);
    // Aucun client Stripe : le compte n'avait jamais rien acheté.
    expect(spies.stripe).not.toHaveBeenCalled();
    expect(spies.webflow).not.toHaveBeenCalled();
    expect(spies.apitemplate).not.toHaveBeenCalled();
  });

  it("supprime le compte même quand un prestataire refuse", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);
    await seedPublishedBook(memo.id, "panne");
    const spies = spyOnProviders();
    spies.apitemplate.mockRejectedValue(new Error("APITemplate en panne"));

    const response = await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode, response.body).toBe(204);
    expect(await harness.prisma.account.count()).toBe(0);
    // La panne de l'un ne retient pas les autres : une trace, une tâche.
    expect(spies.webflow.mock.calls).toEqual([["wf_panne"]]);
  });

  it("reprend en tâche l'effacement des fichiers que le stockage a refusé", async () => {
    const account = await registerAccount(harness.app);
    const storage = harness.context.storage as InMemoryMediaStorage;
    const { storageKey } = await storage.put("photos", "souvenir.jpg", Buffer.from("x"), "image/jpeg");
    const memo = await seedTrip(account.accountId);
    const media = await harness.prisma.mediaAsset.create({
      data: { storageKey, mimeType: "image/jpeg", bytes: 1 },
    });
    await harness.prisma.entry.create({
      data: { memoId: memo.id, kind: "photo", status: "ready", mediaId: media.id },
    });
    const remove = vi.spyOn(storage, "remove").mockRejectedValueOnce(new Error("S3 injoignable"));

    await harness.app.inject({
      method: "DELETE",
      url: "/v1/accounts/me",
      headers: { authorization: account.authorization },
    });

    // Le premier essai échoue, la tâche repasse et efface.
    expect(remove).toHaveBeenCalledTimes(2);
    expect(storage.storedKeys).not.toContain(storageKey);
  });
});

describe("la suppression d'un voyage ou d'un souvenir, chez les prestataires", () => {
  it("efface les photos publiées et le PDF du voyage supprimé", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);
    await seedPublishedBook(memo.id, "voyage");
    const spies = spyOnProviders();

    const response = await harness.app.inject({
      method: "DELETE",
      url: `/v1/memos/${memo.id}`,
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(204);
    expect(spies.webflow.mock.calls).toEqual([["wf_voyage"]]);
    expect(spies.apitemplate.mock.calls).toEqual([["tx_voyage"]]);
    // Le compte reste : son client Stripe aussi.
    expect(spies.stripe).not.toHaveBeenCalled();
  });

  it("retire du CDN la photo d'un souvenir supprimé", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);
    const { entry } = await seedPublishedBook(memo.id, "souvenir");
    const spies = spyOnProviders();

    const response = await harness.app.inject({
      method: "DELETE",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: account.authorization },
    });

    expect(response.statusCode).toBe(204);
    expect(spies.webflow.mock.calls).toEqual([["wf_souvenir"]]);
    // Le carnet reste : son PDF aussi.
    expect(spies.apitemplate).not.toHaveBeenCalled();
  });
});

describe("la tâche d'effacement", () => {
  it("lève quand le prestataire refuse, pour que pg-boss la rejoue", async () => {
    vi.spyOn(harness.context.payments, "deleteCustomer").mockRejectedValue(new Error("Stripe en panne"));

    await expect(
      eraseTrace(harness.context, { provider: "stripe", customerId: "cus_x" }),
    ).rejects.toThrow("Stripe en panne");
  });

  it("insiste plus longtemps que les autres jobs", async () => {
    const queue = new PgBossQueue("postgresql://memobook@localhost:5432/inutilise");
    const boss = (queue as unknown as { boss: { send: (...args: unknown[]) => Promise<unknown> } }).boss;
    const send = vi.spyOn(boss, "send").mockResolvedValue("job");
    (queue as unknown as { started: boolean }).started = true;

    await queue.publish(JOB_NAMES.eraseTrace, { provider: "webflow", assetId: "wf_1" });
    await queue.publish(JOB_NAMES.render, { renderId: "r" });

    expect(send.mock.calls[0]?.[2]).toMatchObject({ retryLimit: 12, retryBackoff: true });
    expect(send.mock.calls[1]?.[2]).toEqual({});
  });
});

describe("les appels aux prestataires", () => {
  it("Stripe : un client déjà supprimé compte comme supprimé", async () => {
    const missing = new Stripe.errors.StripeInvalidRequestError({
      type: "invalid_request_error",
      code: "resource_missing",
      message: "No such customer: 'cus_x'",
    });
    const del = vi.fn().mockRejectedValueOnce(missing).mockRejectedValueOnce(new Error("réseau"));
    const gateway = new StripePaymentGateway({ customers: { del } } as unknown as Stripe, "whsec");

    await expect(gateway.deleteCustomer("cus_x")).resolves.toBeUndefined();
    await expect(gateway.deleteCustomer("cus_x")).rejects.toThrow("réseau");
    expect(del).toHaveBeenCalledWith("cus_x");
  });

  it("Webflow : DELETE /v2/assets/{id}, et un 404 vaut un fichier déjà retiré", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
      .mockResolvedValueOnce(new Response("{}", { status: 404 }))
      .mockResolvedValueOnce(new Response("{}", { status: 429 }));
    vi.stubGlobal("fetch", fetchMock);
    const publisher = new WebflowAssetPublisher("jeton", "site");

    await publisher.unpublish("wf_1");
    await publisher.unpublish("wf_1");
    await expect(publisher.unpublish("wf_1")).rejects.toThrow("HTTP 429");

    expect(fetchMock.mock.calls[0]?.[0]).toBe("https://api.webflow.com/v2/assets/wf_1");
    expect(fetchMock.mock.calls[0]?.[1]).toMatchObject({ method: "DELETE" });
  });

  it("APITemplate : GET /v2/delete-object, et seul `success` vaut effacé", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(Response.json({ status: "success", transaction_ref: "tx_1" }))
      .mockResolvedValueOnce(Response.json({ status: "error", message: "introuvable" }));
    vi.stubGlobal("fetch", fetchMock);
    const renderer = new ApiTemplateRenderer("cle", "modele", "https://rest-de.apitemplate.io/v2");

    await renderer.discard("tx_1");
    await expect(renderer.discard("tx_1")).rejects.toThrow("introuvable");

    expect(String(fetchMock.mock.calls[0]?.[0])).toBe(
      "https://rest-de.apitemplate.io/v2/delete-object?transaction_ref=tx_1",
    );
  });
});
