import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **La modale d'avis, poussée sans livrer de version** (T273).
 *
 * Ce qui se teste ici est la règle d'affichage — qui la voit, combien de fois,
 * et ce qu'il en reste —, parce que c'est elle qui décide si on dérange
 * quelqu'un deux fois.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

/** Une campagne ouverte, avec une question libre et un choix. */
async function seedCampaign(
  overrides: { isActive?: boolean; maxDisplays?: number; audience?: object; key?: string } = {},
) {
  return harness.prisma.feedbackCampaign.create({
    data: {
      key: overrides.key ?? "avis-v1",
      title: "Comment ça se passe ?",
      subtitle: "Deux questions, trente secondes.",
      isActive: overrides.isActive ?? true,
      maxDisplays: overrides.maxDisplays ?? 1,
      ...(overrides.audience ? { audience: overrides.audience } : {}),
      questions: {
        create: [
          { position: 1, kind: "text", prompt: "Qu'est-ce qui te manque ?", placeholder: "Dis-nous…" },
          {
            position: 2,
            kind: "choice",
            prompt: "Tu l'utilises…",
            config: { options: [{ key: "souvent", label: "Souvent" }, { key: "parfois", label: "Parfois" }] },
          },
        ],
      },
    },
    include: { questions: { orderBy: { position: "asc" } } },
  });
}

interface CampaignJson {
  campaign: {
    id: string;
    key: string;
    title: string;
    submitLabel: string;
    questions: { id: string; kind: string; prompt: string | null; config: unknown }[];
  } | null;
}

const read = async (authorization: string) => {
  const response = await harness.app.inject({
    method: "GET",
    url: "/v1/feedback-campaign",
    headers: { authorization },
  });
  expect(response.statusCode).toBe(200);
  return response.json<CampaignJson>();
};

describe("la modale d'avis", () => {
  it("sert la campagne ouverte, ses questions dans l'ordre", async () => {
    const me = await registerAccount(harness.app);
    await seedCampaign();

    const { campaign } = await read(me.authorization);

    expect(campaign?.key).toBe("avis-v1");
    expect(campaign?.title).toBe("Comment ça se passe ?");
    expect(campaign?.submitLabel).toBe("Envoyer");
    expect(campaign?.questions.map((question) => question.kind)).toEqual(["text", "choice"]);
    expect(campaign?.questions[1]?.config).toEqual({
      options: [{ key: "souvent", label: "Souvent" }, { key: "parfois", label: "Parfois" }],
    });
  });

  it("ne sert rien quand le drapeau est baissé", async () => {
    const me = await registerAccount(harness.app);
    await seedCampaign({ isActive: false });

    expect((await read(me.authorization)).campaign).toBeNull();
  });

  /**
   * ⚠️ Tant que `audience` n'est pas évalué, une campagne qui en porte un ne
   * se sert à personne : servie à tout le monde, elle manquerait sa cible
   * **sans le dire**.
   */
  it("ne sert pas une campagne qui vise une audience", async () => {
    const me = await registerAccount(harness.app);
    await seedCampaign({ audience: { hasOrdered: true } });

    expect((await read(me.authorization)).campaign).toBeNull();
  });

  it("ne la montre pas plus que `maxDisplays`", async () => {
    const me = await registerAccount(harness.app);
    await seedCampaign({ maxDisplays: 2 });

    expect((await read(me.authorization)).campaign).not.toBeNull();
    expect((await read(me.authorization)).campaign).not.toBeNull();
    expect((await read(me.authorization)).campaign).toBeNull();
  });

  /** Une campagne vue par l'un n'est pas vue par l'autre. */
  it("compte les affichages par personne", async () => {
    const moi = await registerAccount(harness.app);
    // Une adresse par compte : `registerAccount` crée toujours le même sinon.
    const autre = await registerAccount(harness.app, "autre@memobook.app");
    await seedCampaign({ maxDisplays: 1 });

    expect((await read(moi.authorization)).campaign).not.toBeNull();
    expect((await read(moi.authorization)).campaign).toBeNull();
    expect((await read(autre.authorization)).campaign).not.toBeNull();
  });
});

describe("ce qu'on fait de la modale", () => {
  it("garde les réponses, chacune dans sa colonne", async () => {
    const me = await registerAccount(harness.app);
    const campaign = await seedCampaign();
    await read(me.authorization);

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/feedback-campaigns/${campaign.id}/response`,
      headers: { authorization: me.authorization },
      payload: {
        appVersion: "1.4.2",
        answers: [
          { questionId: campaign.questions[0]!.id, text: "Un mode hors ligne complet." },
          { questionId: campaign.questions[1]!.id, choiceKey: "souvent" },
        ],
      },
    });
    expect(response.statusCode).toBe(204);

    const saved = await harness.prisma.feedbackResponse.findFirstOrThrow({
      where: { campaignId: campaign.id },
      include: { answers: true },
    });
    expect(saved.submittedAt).not.toBeNull();
    expect(saved.dismissedAt).toBeNull();
    expect(saved.appVersion).toBe("1.4.2");
    const texte = saved.answers.find((answer) => answer.questionId === campaign.questions[0]!.id);
    const choix = saved.answers.find((answer) => answer.questionId === campaign.questions[1]!.id);
    expect(texte?.textValue).toBe("Un mode hors ligne complet.");
    expect(choix?.choiceKey).toBe("souvent");
    expect(choix?.textValue).toBeNull();
  });

  /** Fermer est un résultat : on ne la repropose pas, et on sait pourquoi. */
  it("retient qu'elle a été fermée, et ne la repropose plus", async () => {
    const me = await registerAccount(harness.app);
    const campaign = await seedCampaign({ maxDisplays: 5 });
    await read(me.authorization);

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/feedback-campaigns/${campaign.id}/response`,
      headers: { authorization: me.authorization },
      payload: { dismissed: true },
    });
    expect(response.statusCode).toBe(204);

    const saved = await harness.prisma.feedbackResponse.findFirstOrThrow({
      where: { campaignId: campaign.id },
    });
    expect(saved.dismissedAt).not.toBeNull();
    expect(saved.submittedAt).toBeNull();
    expect((await read(me.authorization)).campaign).toBeNull();
  });

  it("répondre deux fois ne fait pas deux avis", async () => {
    const me = await registerAccount(harness.app);
    const campaign = await seedCampaign();
    await read(me.authorization);

    const envoyer = (texte: string) =>
      harness.app.inject({
        method: "POST",
        url: `/v1/feedback-campaigns/${campaign.id}/response`,
        headers: { authorization: me.authorization },
        payload: { answers: [{ questionId: campaign.questions[0]!.id, text: texte }] },
      });

    await envoyer("Une première fois.");
    await envoyer("Et la même, renvoyée.");

    const responses = await harness.prisma.feedbackResponse.findMany({
      where: { campaignId: campaign.id },
      include: { answers: true },
    });
    expect(responses).toHaveLength(1);
    expect(responses[0]?.answers).toHaveLength(1);
    expect(responses[0]?.answers[0]?.textValue).toBe("Et la même, renvoyée.");
  });

  it("écarte une réponse qui vise une question d'ailleurs, sans perdre le reste", async () => {
    const me = await registerAccount(harness.app);
    const campaign = await seedCampaign();
    const ailleurs = await seedCampaign({ key: "autre-campagne", isActive: false });
    await read(me.authorization);

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/feedback-campaigns/${campaign.id}/response`,
      headers: { authorization: me.authorization },
      payload: {
        answers: [
          { questionId: ailleurs.questions[0]!.id, text: "Perdue." },
          { questionId: campaign.questions[0]!.id, text: "Gardée." },
        ],
      },
    });
    expect(response.statusCode).toBe(204);

    const saved = await harness.prisma.feedbackResponse.findFirstOrThrow({
      where: { campaignId: campaign.id },
      include: { answers: true },
    });
    expect(saved.answers).toHaveLength(1);
    expect(saved.answers[0]?.textValue).toBe("Gardée.");
  });

  it("refuse une campagne qui n'existe pas", async () => {
    const me = await registerAccount(harness.app);

    const response = await harness.app.inject({
      method: "POST",
      url: "/v1/feedback-campaigns/8f1a0f74-2a1b-4c3d-9e5f-6a7b8c9d0e1f/response",
      headers: { authorization: me.authorization },
      payload: { dismissed: true },
    });
    expect(response.statusCode).toBe(404);
  });
});
