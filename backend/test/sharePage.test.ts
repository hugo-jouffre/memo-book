import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { tripDates } from "../src/routes/sharePage.js";
import { shareBaseUrl } from "../src/services/shareLink.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Le lien de prévisualisation (T229) : la feuille « Partager » et « Recevoir
 * sur WhatsApp » envoient `POST /v1/memos/:id/share-link`, et ce lien mène
 * désormais quelque part — une page publique servie par l'API.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

async function sharedTrip() {
  const { authorization } = await registerAccount(harness.app);
  const created = await harness.app.inject({
    method: "POST",
    url: "/v1/trips",
    headers: { authorization },
    payload: { title: "Lisbonne <entre filles>", startDate: "2026-05-02", endDate: "2026-05-09" },
  });
  const memoId = created.json<{ trip: { id: string } }>().trip.id;
  await harness.prisma.memo.update({
    where: { id: memoId },
    data: { coverPhotoUrl: "https://cdn.example.com/couverture.jpg" },
  });
  await harness.prisma.entry.create({
    data: {
      memoId,
      kind: "text",
      transcript: "euh alors on est arrivées",
      redactedText: "On est arrivées à l’Alfama sous une pluie tiède, les valises pleines de sable.",
      capturedAt: new Date("2026-05-02T18:00:00Z"),
    },
  });
  await harness.prisma.memoStep.create({ data: { memoId, number: 1, placeName: "Alfama" } });

  const link = await harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/share-link`,
    headers: { authorization },
  });
  expect(link.statusCode).toBe(201);
  return { memoId, authorization, url: link.json<{ url: string }>().url };
}

describe("le lien de prévisualisation", () => {
  it("vit sur l'hôte de l'API, et rend toujours le même", async () => {
    const { memoId, authorization, url } = await sharedTrip();
    expect(url).toMatch(new RegExp(`^${shareBaseUrl(harness.context.env)}/c/[A-Za-z0-9_-]{16}$`));
    expect(url).not.toContain("memo-book.com");

    const again = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/share-link`,
      headers: { authorization },
    });
    expect(again.statusCode).toBe(200);
    expect(again.json<{ url: string }>().url).toBe(url);

    const preview = await harness.app.inject({
      method: "GET",
      url: `/v1/memos/${memoId}/preview`,
      headers: { authorization },
    });
    expect(preview.json<{ shareUrl: string }>().shareUrl).toBe(url);
  });

  it("ouvre une page publique, avec ce qu'il faut pour la vignette WhatsApp", async () => {
    const { url } = await sharedTrip();
    const page = await harness.app.inject({ method: "GET", url: new URL(url).pathname });

    expect(page.statusCode).toBe(200);
    expect(page.headers["content-type"]).toContain("text/html");
    const html = page.body;
    expect(html).toContain('<meta property="og:title" content="Lisbonne &lt;entre filles&gt;">');
    expect(html).toContain('<meta property="og:image" content="https://cdn.example.com/couverture.jpg">');
    expect(html).toContain(`<meta property="og:url" content="${url}">`);
    expect(html).toContain("og:description");
    expect(html).toContain("Alfama sous une pluie tiède");
    expect(html).toContain("<li>Alfama</li>");
    expect(html).toContain("du 2 au 9 mai 2026");
    // Le texte relu, jamais la transcription brute.
    expect(html).not.toContain("euh alors");
  });

  it("répond une page 404 à un jeton inconnu", async () => {
    const page = await harness.app.inject({ method: "GET", url: "/c/inconnuinconnu12" });
    expect(page.statusCode).toBe(404);
    expect(page.body).toContain("Ce carnet n’est plus partagé");
  });

  it("dit les dates comme on les dit", () => {
    expect(tripDates(new Date("2026-05-02"), new Date("2026-06-09"))).toBe("du 2 mai au 9 juin 2026");
    expect(tripDates(new Date("2026-12-28"), new Date("2027-01-03"))).toBe("du 28 décembre 2026 au 3 janvier 2027");
    expect(tripDates(new Date("2026-05-02"), null)).toBe("depuis le 2 mai 2026");
    expect(tripDates(null, null)).toBeNull();
  });
});
