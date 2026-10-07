import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import yauzl from "yauzl";
import { hashSessionToken } from "../src/lib/auth.js";
import {
  DATA_EXPORT_COOLDOWN_MINUTES,
  DATA_EXPORT_MAX_DOWNLOADS,
  findDataExport,
} from "../src/services/dataExport.js";
import { dataExportUrl, type DataExportMail, type Mailer } from "../src/services/mailer.js";
import { renderDataExportMail } from "../src/services/mailTemplates.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * « Exporter mes données » de bout en bout : la demande et son e-mail, la page
 * du lien, et l'archive — relue fichier par fichier, sommes de contrôle
 * comprises, par le même auteur que la bibliothèque qui l'écrit.
 */

/** Un expéditeur qui garde ce qu'il aurait envoyé, et qu'on peut faire échouer. */
function recordingMailer() {
  const sent: DataExportMail[] = [];
  const state = { failing: false };
  const mailer: Mailer = {
    async sendPasswordReset() {},
    async sendDataExport(message) {
      if (state.failing) throw new Error("Resend a refusé l’envoi (422) : domaine non vérifié");
      sent.push(message);
    },
    async sendSubscriptionReminder() {},
  };
  return { mailer, sent, state };
}

const outbox = recordingMailer();
let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness({ mailer: outbox.mailer });
  await resetDatabase(harness.prisma);
  outbox.sent.length = 0;
  outbox.state.failing = false;
});

afterEach(() => {
  vi.restoreAllMocks();
});

afterAll(async () => {
  await harness?.close();
});

async function requestExport(authorization: string) {
  return harness.app.inject({
    method: "POST",
    url: "/v1/accounts/me/export",
    headers: { authorization },
  });
}

/** Le secret du dernier lien envoyé. */
function lastToken(): string {
  const mail = outbox.sent.at(-1);
  if (!mail) throw new Error("Aucun e-mail d’export n’est parti.");
  return mail.token;
}

/** Relit un ZIP entier : nom de chaque fichier, et son contenu vérifié. */
function readZip(buffer: Buffer): Promise<Map<string, Buffer>> {
  return new Promise((resolve, reject) => {
    yauzl.fromBuffer(buffer, { lazyEntries: true }, (error, zip) => {
      if (error || !zip) return reject(error ?? new Error("ZIP illisible"));
      const files = new Map<string, Buffer>();
      zip.on("error", reject);
      zip.on("end", () => resolve(files));
      zip.on("entry", (entry: yauzl.Entry) => {
        zip.openReadStream(entry, (streamError, stream) => {
          if (streamError || !stream) return reject(streamError ?? new Error("Entrée illisible"));
          const chunks: Buffer[] = [];
          stream.on("data", (chunk: Buffer) => chunks.push(chunk));
          stream.on("error", reject);
          stream.on("end", () => {
            files.set(entry.fileName, Buffer.concat(chunks));
            zip.readEntry();
          });
        });
      });
      zip.readEntry();
    });
  });
}

describe("POST /v1/accounts/me/export", () => {
  it("demande une session", async () => {
    const response = await harness.app.inject({ method: "POST", url: "/v1/accounts/me/export" });
    expect(response.statusCode).toBe(401);
    expect(outbox.sent).toHaveLength(0);
  });

  it("envoie le lien à l’adresse du compte, valable sept jours, et n’en garde que l’empreinte", async () => {
    const { accountId, authorization } = await registerAccount(harness.app, "hugo@memobook.app");
    const before = Date.now();

    const response = await requestExport(authorization);

    expect(response.statusCode).toBe(202);
    const body = response.json<{ email: string; expiresAt: string; alreadyRequested: boolean }>();
    expect(body.email).toBe("hugo@memobook.app");
    expect(body.alreadyRequested).toBe(false);
    const days = (new Date(body.expiresAt).getTime() - before) / (24 * 60 * 60 * 1000);
    expect(days).toBeGreaterThan(6.99);
    expect(days).toBeLessThan(7.01);

    expect(outbox.sent).toHaveLength(1);
    const [mail] = outbox.sent;
    expect(mail?.to).toBe("hugo@memobook.app");
    expect(mail?.firstName).toBe("Hugo");

    const rows = await harness.prisma.dataExport.findMany({ where: { accountId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]?.tokenHash).toBe(hashSessionToken(lastToken()));
    expect(rows[0]?.tokenHash).not.toContain(lastToken());
  });

  it("n’envoie pas un second e-mail moins de cinq minutes après le premier", async () => {
    const { authorization } = await registerAccount(harness.app);
    await requestExport(authorization);

    const again = await requestExport(authorization);

    expect(again.statusCode).toBe(202);
    expect(again.json<{ alreadyRequested: boolean }>().alreadyRequested).toBe(true);
    expect(outbox.sent).toHaveLength(1);
  });

  it("une nouvelle demande remplace le lien précédent", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await requestExport(authorization);
    const first = lastToken();

    // La première demande a vieilli au-delà du délai.
    await harness.prisma.dataExport.updateMany({
      where: { accountId },
      data: { createdAt: new Date(Date.now() - (DATA_EXPORT_COOLDOWN_MINUTES + 1) * 60 * 1000) },
    });
    const response = await requestExport(authorization);

    expect(response.json<{ alreadyRequested: boolean }>().alreadyRequested).toBe(false);
    expect(outbox.sent).toHaveLength(2);
    expect((await findDataExport(harness.prisma, first)).status).toBe("invalid");
    expect((await findDataExport(harness.prisma, lastToken())).status).toBe("valid");
  });

  it("un envoi raté ne laisse rien derrière lui, et ne coupe pas le lien qui marche", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await requestExport(authorization);
    const working = lastToken();
    await harness.prisma.dataExport.updateMany({
      where: { accountId },
      data: { createdAt: new Date(Date.now() - (DATA_EXPORT_COOLDOWN_MINUTES + 1) * 60 * 1000) },
    });

    outbox.state.failing = true;
    const response = await requestExport(authorization);

    expect(response.statusCode).toBe(503);
    expect(response.json<{ error: string }>().error).toBe("email_unavailable");
    expect(await harness.prisma.dataExport.count({ where: { accountId } })).toBe(1);
    expect((await findDataExport(harness.prisma, working)).status).toBe("valid");

    // Et rien ne bloque la suivante.
    outbox.state.failing = false;
    const retry = await requestExport(authorization);
    expect(retry.json<{ alreadyRequested: boolean }>().alreadyRequested).toBe(false);
  });

  it("refuse en le disant quand le compte n’a pas d’adresse", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await harness.prisma.account.update({ where: { id: accountId }, data: { email: null } });

    const response = await requestExport(authorization);

    expect(response.statusCode).toBe(409);
    expect(response.json<{ error: string }>().error).toBe("no_email");
    expect(outbox.sent).toHaveLength(0);
  });
});

describe("L’e-mail", () => {
  it("porte le lien de la page, et dit jusqu’à quand il vaut", () => {
    const url = "https://api.memo-book.test/data-export?token=abc%2Bdef";
    const mail = renderDataExportMail(
      { to: "hugo@memobook.app", firstName: "Hugo", token: "abc+def", expiresAt: new Date("2026-10-08T15:00:00Z") },
      url,
    );

    expect(mail.subject).toBe("Tes données MemoBook sont prêtes");
    expect(mail.html).toContain('href="https://api.memo-book.test/data-export?token=abc%2Bdef"');
    expect(mail.text).toContain(url);
    expect(mail.text).toContain("jusqu’au jeudi 8 octobre 2026");
    expect(mail.text).toContain("Bonjour Hugo,");
    expect(mail.text).toContain("ne le transfère à personne");
  });

  it("vise la page de l’API, sur son adresse publique", () => {
    const url = dataExportUrl(
      { ...harness.context.env, API_PUBLIC_BASE_URL: "", RAILWAY_PUBLIC_DOMAIN: "api-production-9f35a.up.railway.app" },
      "a/b",
    );
    expect(url).toBe("https://api-production-9f35a.up.railway.app/data-export?token=a%2Fb");
  });
});

describe("La page du lien", () => {
  it("résume l’archive et propose de la télécharger", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await harness.prisma.memo.create({
      data: { ownerAccountId: accountId, title: "Rome 2026", accessCode: "EXPPG1" },
    });
    await requestExport(authorization);
    const token = lastToken();

    const response = await harness.app.inject({ method: "GET", url: `/data-export?token=${encodeURIComponent(token)}` });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("text/html");
    expect(response.headers["cache-control"]).toBe("no-store");
    expect(response.headers["referrer-policy"]).toBe("no-referrer");
    expect(response.body).toContain("Télécharger mes données");
    expect(response.body).toContain("1 voyage · 0 souvenir");
    expect(response.body).toContain(`/data-export/archive?token=${encodeURIComponent(token)}`);
    // Ouvrir la page ne compte pas comme un téléchargement.
    expect((await harness.prisma.dataExport.findFirstOrThrow()).downloadCount).toBe(0);
  });

  it("répond en mots quand le lien manque, ne vaut rien, a expiré ou a trop servi", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await requestExport(authorization);
    const token = lastToken();
    const page = (value: string) => harness.app.inject({ method: "GET", url: `/data-export?token=${encodeURIComponent(value)}` });

    const incomplete = await harness.app.inject({ method: "GET", url: "/data-export" });
    expect(incomplete.statusCode).toBe(400);
    expect(incomplete.body).toContain("Ce lien est incomplet");

    const unknown = await page("pas-un-vrai-lien");
    expect(unknown.statusCode).toBe(410);
    expect(unknown.body).toContain("Ce lien n’est plus valable");

    await harness.prisma.dataExport.updateMany({ where: { accountId }, data: { downloadCount: DATA_EXPORT_MAX_DOWNLOADS } });
    expect((await page(token)).statusCode).toBe(429);
    const archive = await harness.app.inject({ method: "GET", url: `/data-export/archive?token=${encodeURIComponent(token)}` });
    expect(archive.statusCode).toBe(429);
    expect(archive.headers["content-type"]).toContain("text/html");

    await harness.prisma.dataExport.updateMany({
      where: { accountId },
      data: { downloadCount: 0, expiresAt: new Date(Date.now() - 1000) },
    });
    expect((await page(token)).statusCode).toBe(410);
  });

  it("meurt avec le compte", async () => {
    const { authorization } = await registerAccount(harness.app);
    await requestExport(authorization);
    const token = lastToken();

    await harness.app.inject({ method: "DELETE", url: "/v1/accounts/me", headers: { authorization } });

    const response = await harness.app.inject({ method: "GET", url: `/data-export?token=${encodeURIComponent(token)}` });
    expect(response.statusCode).toBe(410);
  });
});

describe("L’archive", () => {
  it("contient le compte, ses voyages et leurs médias — et rien de ce qui n’est pas à lui", async () => {
    const { prisma, context } = harness;
    const me = await registerAccount(harness.app, "hugo@memobook.app");
    const clara = await registerAccount(harness.app, "clara@memobook.app");
    const stranger = await registerAccount(harness.app, "inconnu@memobook.app");
    await prisma.account.update({
      where: { id: clara.accountId },
      data: { firstName: "Clara", phoneNumber: "+33 6 11 11 11 11" },
    });
    await prisma.account.update({
      where: { id: me.accountId },
      data: { phoneNumber: "+33 6 22 22 22 22", birthDate: new Date("1994-05-12T00:00:00Z") },
    });

    // Rome : à Hugo. Une photo, un texte corrigé à la main, un vocal dont le
    // fichier a disparu du stockage, un vocal de contexte et un carnet.
    const photo = await context.storage.put("photos", "rome.jpg", Buffer.from("JPEG-ROME"), "image/jpeg");
    const voice = await context.storage.put("audio", "contexte.m4a", Buffer.from("M4A-CONTEXTE"), "audio/m4a");
    const rome = await prisma.memo.create({
      data: {
        ownerAccountId: me.accountId,
        title: "Rome 2026 — Trastevere !",
        accessCode: "EXPAR1",
        destinationCity: "Rome",
        destinationName: "Italie",
        startDate: new Date("2026-08-26T00:00:00Z"),
        endDate: new Date("2026-09-15T00:00:00Z"),
      },
    });
    const photoAsset = await prisma.mediaAsset.create({
      data: { storageKey: photo.storageKey, mimeType: "image/jpeg", bytes: photo.bytes },
    });
    const ghostAsset = await prisma.mediaAsset.create({
      data: { storageKey: "audio/disparu.m4a", mimeType: "audio/m4a", bytes: 12 },
    });
    await prisma.entry.create({
      data: {
        memoId: rome.id,
        kind: "photo",
        status: "ready",
        mediaId: photoAsset.id,
        placeLabel: "Trastevere",
        capturedAt: new Date("2026-08-27T12:30:00Z"),
      },
    });
    await prisma.entry.create({
      data: {
        memoId: rome.id,
        kind: "text",
        status: "ready",
        transcript: "on a mangé des suppli",
        redactedText: "Nous avons goûté nos premiers supplì.",
        editedText: "Premiers supplì au coin de la rue.",
        suggestedTitle: "Les supplì",
        capturedAt: new Date("2026-08-27T17:00:00Z"),
      },
    });
    await prisma.entry.create({
      data: {
        memoId: rome.id,
        kind: "audio",
        status: "ready",
        mediaId: ghostAsset.id,
        transcript: "Le Colisée au coucher du soleil.",
        capturedAt: new Date("2026-08-28T18:00:00Z"),
      },
    });
    await prisma.chatMessage.create({
      data: { memoId: rome.id, author: "traveller", kind: "text", accountId: me.accountId, text: "Bonjour MEMO" },
    });
    await prisma.chatMessage.create({
      data: { memoId: rome.id, author: "memo", kind: "text", text: "Raconte-moi Rome !" },
    });
    await prisma.chatMessage.create({
      data: {
        memoId: rome.id,
        author: "traveller",
        kind: "voice",
        accountId: me.accountId,
        payload: { contextVoice: { storageKey: voice.storageKey, mimeType: "audio/m4a", durationSeconds: 3 } },
      },
    });
    await prisma.render.create({
      data: { memoId: rome.id, status: "ready", pdfUrl: "https://pdf.memobook.test/rome.pdf" },
    });
    // Le compteur du crédit du jour (politique de confidentialité, § 2.6).
    await prisma.tripDailyUsage.create({
      data: {
        memoId: rome.id,
        day: new Date("2026-08-27T00:00:00Z"),
        usedMs: 300_000,
        voiceMs: 240_000,
        textCharacters: 800,
        limitNotifiedAt: new Date("2026-08-27T19:00:00Z"),
      },
    });
    await prisma.account.update({ where: { id: me.accountId }, data: { timeZone: "Europe/Rome" } });
    await prisma.accountConnector.create({
      data: {
        accountId: me.accountId,
        connectorKey: "strava",
        isEnabled: true,
        accessToken: "jeton-strava-tres-secret",
        externalAccountLabel: "hugo_court",
      },
    });

    // Lisbonne : à Clara, Hugo y est co-voyageur.
    const lisbon = await prisma.memo.create({
      data: {
        ownerAccountId: clara.accountId,
        title: "Lisbonne",
        accessCode: "EXPAR2",
        members: { create: { accountId: me.accountId, status: "active", acceptedAt: new Date() } },
      },
    });
    await prisma.entry.create({
      data: { memoId: lisbon.id, kind: "text", status: "ready", transcript: "Pastéis de nata à Belém." },
    });
    await prisma.chatMessage.create({
      data: { memoId: lisbon.id, author: "traveller", kind: "text", accountId: clara.accountId, text: "Coucou, c’est Clara" },
    });

    // Ce qu'il a écrit à l'équipe, et un vote de la foire aux questions (T226).
    await prisma.supportMessage.create({
      data: { accountId: me.accountId, source: "founders_note", message: "Bravo pour le carnet !" },
    });
    await prisma.faqVote.create({ data: { accountId: me.accountId, questionId: "faq.carnet.pages", isHelpful: true } });

    // Un voyage qui n'est pas le sien.
    await prisma.memo.create({
      data: { ownerAccountId: stranger.accountId, title: "Voyage d’un autre", accessCode: "EXPAR3" },
    });

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      return url === "https://pdf.memobook.test/rome.pdf"
        ? new Response("%PDF-1.7 carnet de Rome")
        : new Response("", { status: 404 });
    });

    await requestExport(me.authorization);
    const response = await harness.app.inject({
      method: "GET",
      url: `/data-export/archive?token=${encodeURIComponent(lastToken())}`,
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toBe("application/zip");
    expect(response.headers["content-disposition"]).toMatch(
      /^attachment; filename="memobook-donnees-\d{4}-\d{2}-\d{2}\.zip"$/,
    );
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    const files = await readZip(response.rawPayload);
    const root = [...files.keys()][0]!.split("/")[0]!;
    const read = (path: string) => files.get(`${root}/${path}`)?.toString("utf8");
    const json = <T>(path: string) => JSON.parse(read(path) ?? "null") as T;

    // Le compte.
    const account = json<{
      email: string;
      phoneNumber: string;
      birthDate: string;
      timeZone: string | null;
      signIn: { hasPassword: boolean };
    }>("compte.json");
    expect(account.email).toBe("hugo@memobook.app");
    expect(account.phoneNumber).toBe("+33 6 22 22 22 22");
    expect(account.birthDate).toBe("1994-05-12");
    expect(account.signIn.hasPassword).toBe(true);
    expect(account.timeZone).toBe("Europe/Rome");

    // Ses deux voyages, dans l'ordre, et pas celui d'un autre.
    const trips = [...new Set([...files.keys()].filter((name) => name.includes("/voyages/")).map((name) => name.split("/")[2]))];
    expect(trips).toEqual(["01-rome-2026-trastevere", "02-lisbonne"]);

    const romeTrip = json<{
      yourRole: string;
      books: { file: string; orderedByYou: boolean }[];
      dailyCredit: unknown[];
    }>("voyages/01-rome-2026-trastevere/voyage.json");
    expect(romeTrip.yourRole).toBe("owner");
    // Le crédit du jour, jour par jour (03/10/2026).
    expect(romeTrip.dailyCredit).toEqual([
      {
        day: "2026-08-27",
        usedMs: 300_000,
        voiceMs: 240_000,
        textCharacters: 800,
        limitNotifiedAt: "2026-08-27T19:00:00.000Z",
      },
    ]);
    expect(romeTrip.books.map((book) => [book.file, book.orderedByYou])).toEqual([["carnet.pdf", false]]);
    expect(json<{ yourRole: string }>("voyages/02-lisbonne/voyage.json").yourRole).toBe("coTraveller");

    // Les médias, octet pour octet — la photo à l'heure de Paris.
    expect(read("voyages/01-rome-2026-trastevere/carnet.pdf")).toBe("%PDF-1.7 carnet de Rome");
    const photoPath = [...files.keys()].find((name) => name.includes("/souvenirs/2026-08-27_14-30_photo_"));
    expect(photoPath).toBeDefined();
    expect(files.get(photoPath!)?.toString()).toBe("JPEG-ROME");
    const voicePath = [...files.keys()].find((name) => name.includes("/conversation/") && name.endsWith(".m4a"));
    expect(files.get(voicePath!)?.toString()).toBe("M4A-CONTEXTE");

    // Le texte corrigé à la main fait autorité dans le récit.
    const story = read("voyages/01-rome-2026-trastevere/recit.txt") ?? "";
    expect(story).toContain("Les supplì");
    expect(story).toContain("Premiers supplì au coin de la rue.");
    expect(story).toContain("Du 26 août 2026 au 15 septembre 2026 · Rome, Italie");

    const memories = json<{ text: { final: string; transcript: string; editedByYou: string } }[]>(
      "voyages/01-rome-2026-trastevere/souvenirs.json",
    );
    expect(memories[1]?.text).toMatchObject({
      final: "Premiers supplì au coin de la rue.",
      transcript: "on a mangé des suppli",
      editedByYou: "Premiers supplì au coin de la rue.",
    });

    // Le récit partagé : les mots de Clara, et son prénom — rien d'autre d'elle.
    const thread = json<{ author: string; name: string | null; text: string }[]>("voyages/02-lisbonne/conversation.json");
    expect(thread).toContainEqual(expect.objectContaining({ author: "coTraveller", name: "Clara", text: "Coucou, c’est Clara" }));

    const support = json<{ messages: { from: string; message: string }[]; faqVotes: { question: string; helpful: boolean }[] }>(
      "support.json",
    );
    expect(support.messages).toEqual([expect.objectContaining({ from: "Mot des fondateurs", message: "Bravo pour le carnet !" })]);
    expect(support.faqVotes).toEqual([expect.objectContaining({ question: "faq.carnet.pages", helpful: true })]);

    // Le fichier disparu n'empêche rien : il est nommé dans le LISEZ-MOI.
    const readme = read("LISEZ-MOI.txt") ?? "";
    expect(readme).toContain("Fichiers absents");
    expect(readme).toContain("son crédit du jour");
    expect(readme).toMatch(/voyages\/01-rome-2026-trastevere\/souvenirs\/2026-08-28_20-00_vocal_[0-9a-f]{8}\.m4a/);

    // Ce qui ne doit jamais sortir.
    const everything = [...files.values()].map((file) => file.toString("utf8")).join("\n");
    const hash = (await prisma.account.findUniqueOrThrow({ where: { id: me.accountId } })).passwordHash!;
    expect(everything).not.toContain(hash);
    expect(everything).not.toContain("jeton-strava-tres-secret");
    expect(everything).not.toContain(lastToken());
    expect(everything).not.toContain("+33 6 11 11 11 11");
    expect(everything).not.toContain("inconnu@memobook.app");
    expect(everything).not.toContain("Voyage d’un autre");

    // Le téléchargement est compté.
    expect((await prisma.dataExport.findFirstOrThrow({ where: { accountId: me.accountId } })).downloadCount).toBe(1);
    // Trois comptes, deux voyages et une vingtaine de lignes sur une base
    // distante : chaque aller-retour coûte des dizaines de millisecondes.
  }, 120_000);
});
