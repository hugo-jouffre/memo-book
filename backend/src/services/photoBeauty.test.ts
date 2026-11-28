import type OpenAI from "openai";
import { describe, expect, it } from "vitest";
import { LlmBeautyJudge, readScores } from "./photoBeauty.js";
import { photosLesPlusNettes, type PhotoQuality } from "./photoPicking.js";
import { LlmRelevanceJudge } from "./photoRelevance.js";

/**
 * **Ce que vaut une photo à regarder** (T265, 23/11/2026) : ce que le modèle
 * rend, et ce que sa note change au moment de choisir.
 */

type Photo = { nom: string } & PhotoQuality;

const choisir = (photos: Photo[], combien: number) =>
  photosLesPlusNettes(photos, combien, (photo) => photo).map((photo) => photo.nom);

describe("relire ce que le juge rend", () => {
  const connues = new Set(["a", "b"]);

  it("garde les notes bien formées, bornées à 0–100", () => {
    const rendu = '{"photos":[{"photo_id":"a","score":87.4},{"photo_id":"b","score":140}]}';
    expect(readScores(rendu, connues)).toEqual([
      { id: "a", score: 87 },
      { id: "b", score: 100 },
    ]);
  });

  /**
   * Un modèle rend n'importe quoi un jour sur cent. Une entrée douteuse
   * s'écarte seule : les autres notes restent, et la photo écartée se rangera
   * sur sa netteté.
   */
  it("écarte ce qui ne se lit pas, sans perdre le reste", () => {
    const rendu = [
      '{"photos":[',
      '{"photo_id":"inventee","score":90},',
      '{"photo_id":"a","score":"beaucoup"},',
      '{"photo_id":"b","score":42},',
      '{"photo_id":"b","score":10}',
      "]}",
    ].join("");
    expect(readScores(rendu, connues)).toEqual([{ id: "b", score: 42 }]);
  });

  it("ne tombe pas sur un JSON tordu ni sur rien du tout", () => {
    expect(readScores("{pas du json", connues)).toEqual([]);
    expect(readScores(null, connues)).toEqual([]);
    expect(readScores('{"photos":"beaucoup"}', connues)).toEqual([]);
  });
});

/**
 * **La beauté passe avant la netteté.** La netteté seule gardait la photo
 * nette d'un mur plutôt que la photo un peu molle d'un visage.
 */
describe("la note du juge dans le choix", () => {
  it("préfère la belle à la nette", () => {
    const photos: Photo[] = [
      { nom: "mur-net", sharpness: 300, beauty: 10 },
      { nom: "visage-mou", sharpness: 60, beauty: 90 },
    ];
    expect(choisir(photos, 1)[0]).toBe("visage-mou");
  });

  /**
   * 🔴 **Ce test disait « ne sauve pas une photo refusée » jusqu'au
   * 28/11/2026** (T310). Le verdict dont il parlait mesure le contraste et
   * non le flou : il écartait les photos unies, pas les floues.
   *
   * Ce qui reste vrai, et que le test garde : **une photo vraiment floue ne
   * se rattrape pas en étant jolie** — mais c'est ``blur`` qui le dit
   * maintenant, et il est sous la beauté, donc une photo un peu molle d'un
   * visage passe toujours devant une photo nette d'un mur. Ici l'écart de
   * flou est franc et les beautés proches : c'est la nette qui gagne.
   */
  it("ne sauve pas une photo franchement floue", () => {
    const photos: Photo[] = [
      { nom: "floue-un-peu-plus-belle", blur: 0.84, beauty: 50 },
      { nom: "nette", blur: 0.27, beauty: 50 },
    ];
    expect(choisir(photos, 1)[0]).toBe("nette");
  });

  /**
   * Une photo que le juge n'a pas vue se range **au milieu** : on ne la
   * privilégie pas, on ne la condamne pas pour une note qui manque. C'est la
   * doctrine de la netteté absente, appliquée à la note — et elle compte,
   * parce qu'un carnet mêle toujours des photos notées et des photos qui
   * viennent d'arriver.
   */
  it("ne condamne pas une photo pas encore notée", () => {
    const photos: Photo[] = [
      { nom: "mediocre", sharpness: 200, beauty: 20 },
      { nom: "pas-notee", sharpness: 100 },
      { nom: "belle", sharpness: 100, beauty: 80 },
    ];
    // La fonction réordonne, elle ne tronque pas : les écartées restent
    // derrière, dans leur ordre.
    expect(choisir(photos, 2)).toEqual(["pas-notee", "belle", "mediocre"]);
  });

  it("départage deux notes égales sur la netteté, puis sur l'ordre", () => {
    const photos: Photo[] = [
      { nom: "1", sharpness: 50, beauty: 70 },
      { nom: "2", sharpness: 150, beauty: 70 },
      { nom: "3", sharpness: 150, beauty: 70 },
    ];
    expect(choisir(photos, 2)).toEqual(["2", "3", "1"]);
  });

  /** Sans aucune note — le juge éteint —, rien ne change : c'est le repli. */
  it("se comporte comme avant quand personne n'est noté", () => {
    const photos: Photo[] = [
      { nom: "floue", sharpness: 12 },
      { nom: "nette", sharpness: 180 },
    ];
    expect(choisir(photos, 1)[0]).toBe("nette");
  });
});

/**
 * **Ce que le juge envoie vraiment** — le test qui manquait le 23/11/2026.
 *
 * La première composition réelle a rendu zéro note : les modèles récents
 * refusent `max_tokens` d'un `400 Unsupported parameter`, et le motif recopié
 * de `stickerVision.ts` l'employait, parce que `gpt-4o-mini` l'accepte
 * encore. Rien ne l'avait vu — les tests relisaient la réponse du modèle,
 * jamais la requête.
 *
 * Un faux client suffit : on ne vérifie pas que le modèle répond, on vérifie
 * ce qu'on lui demande.
 */
describe("la requête envoyée au modèle", () => {
  function clientQuiNote(): { client: OpenAI; vus: Record<string, unknown>[] } {
    const vus: Record<string, unknown>[] = [];
    const client = {
      chat: {
        completions: {
          create: async (params: Record<string, unknown>) => {
            vus.push(params);
            return { choices: [{ message: { content: '{"photos":[]}' } }] };
          },
        },
      },
    } as unknown as OpenAI;
    return { client, vus };
  }

  const photo = { id: "a", jpeg: Buffer.from([0xff, 0xd8, 0xff]) };

  it("borne la réponse avec `max_completion_tokens`, jamais `max_tokens`", async () => {
    const { client, vus } = clientQuiNote();
    await new LlmBeautyJudge(client, "gpt-5.6-luna").score([photo]);

    const params = vus[0] ?? {};
    expect(params["max_completion_tokens"], "Le paramètre que les modèles récents acceptent.").toBeTypeOf(
      "number",
    );
    expect(params["max_tokens"], "Celui qu'ils refusent d'un 400.").toBeUndefined();
  });

  it("le juge de la pertinence envoie la même chose", async () => {
    const { client, vus } = clientQuiNote();
    await new LlmRelevanceJudge(client, "gpt-5.6-luna").score("Une journée à Naxos.", [photo]);

    const params = vus[0] ?? {};
    expect(params["max_completion_tokens"]).toBeTypeOf("number");
    expect(params["max_tokens"]).toBeUndefined();
  });

  /** La photo part réduite et en `detail: "low"` : c'est ce qui tient le prix. */
  it("montre la photo en basse définition", async () => {
    const { client, vus } = clientQuiNote();
    await new LlmBeautyJudge(client, "gpt-5.6-luna").score([photo]);

    const messages = (vus[0]?.["messages"] ?? []) as { role: string; content: unknown }[];
    const contenu = JSON.stringify(messages.find((message) => message.role === "user")?.content ?? "");
    expect(contenu).toContain('"detail":"low"');
  });
});
