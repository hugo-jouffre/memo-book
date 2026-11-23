import type { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import { bookCoversOf, coverPhotoEntryIds } from "../services/bookCovers.js";
import { currentBookFingerprint } from "../services/bookFingerprint.js";
import { applyBookSettings, keepsPhotos } from "../services/bookSettings.js";
import { validatePayload } from "../services/payloadValidator.js";
import {
  ouvrirLesChapitresSurUneCarte,
  premiereEtapeAGauche,
  quizForBook,
  withBestPhotosFirst,
  type StructuringEntry,
} from "../services/structuring.js";
import { parseTripContext } from "../services/tripContext.js";
import { refreshTripFactsQuietly } from "../services/tripFacts.js";
import { renderablePhotoUrl } from "../services/renderPhotos.js";
import { settlePhotoBeauty } from "../services/photoBeautyPass.js";
import { noterLaPertinence, type PhotoSource } from "../services/photoRelevancePass.js";
import { photoStickersOf, settlePhotoStickers } from "../services/photoStickers.js";
import { JOB_NAMES } from "./queue.js";
import { finalTextOf } from "./redact.js";
import type { RenderJob } from "./render.js";
import { isSimulatedCdnUrl } from "../services/webflow.js";

export interface StructureJob {
  renderId: string;
}

/**
 * Combien de temps la mise en page attend les souvenirs encore en rédaction,
 * et à quel pas elle regarde. Une variable et non une constante : les tests la
 * raccourcissent.
 *
 * **Attendre plutôt qu'échouer** (07/10/2026) : l'aperçu lance désormais une
 * composition à chaque ouverture (T224), y compris trente secondes après le
 * dernier vocal, quand MEMO n'a pas fini de l'écrire. Échouer aussitôt
 * laissait l'aperçu sur « La composition n'a pas abouti » pour un souvenir
 * qui serait prêt dans l'instant ; trois minutes couvrent une rédaction lente.
 */
export const STRUCTURE_TIMING = { redactionWaitMs: 3 * 60 * 1000, pollMs: 5_000 };

/** Les souvenirs de ce carnet que la rédaction n'a pas encore rendus. */
export function pendingRedactionCount(
  prisma: AppContext["prisma"],
  memoId: string,
): Promise<number> {
  return prisma.entry.count({
    where: { memoId, kind: { not: "photo" }, redactionStatus: { in: ["pending", "processing"] } },
  });
}

async function waitForRedactions(prisma: AppContext["prisma"], memoId: string): Promise<number> {
  const deadline = Date.now() + STRUCTURE_TIMING.redactionWaitMs;
  let pending = await pendingRedactionCount(prisma, memoId);
  while (pending > 0 && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, STRUCTURE_TIMING.pollMs));
    pending = await pendingRedactionCount(prisma, memoId);
  }
  return pending;
}

/**
 * Étape 3 : les textes validés deviennent un payload de carnet conforme au
 * schéma de `MemoBook Generator/templates/travel-journal/`. Le payload est validé ici, avant
 * d'atteindre APITemplate — un payload hors limites produit un PDF qui déborde
 * de la page, ce qui ne se voit qu'à l'impression.
 *
 * Cette étape ne réécrit rien : elle arrange. Le texte lui arrive fini de
 * l'étape de rédaction, éventuellement corrigé à la main par le voyageur.
 */
export async function structureRender(
  context: AppContext,
  { renderId }: StructureJob,
): Promise<void> {
  const { prisma, structurer, queue, logger } = context;

  const found = await prisma.render.findUnique({ where: { id: renderId }, select: { memoId: true } });

  if (!found) {
    logger.warn({ renderId }, "Rendu introuvable, job de structuration ignoré");
    return;
  }

  await prisma.render.update({
    where: { id: renderId },
    data: { status: "processing", error: null },
  });

  try {
    // Les souvenirs encore en rédaction d'abord — voir `STRUCTURE_TIMING`.
    // Le carnet se relit **après** l'attente : ce sont leurs textes finis qu'on
    // veut.
    await waitForRedactions(prisma, found.memoId);
    // Les chiffres du dos de couverture à jour avant de composer — les jours
    // d'un voyage en cours avancent sans qu'aucun souvenir n'arrive (T227).
    await refreshTripFactsQuietly(context, found.memoId);

    // **Ce que chaque photo vaut à regarder** (T265, 23/11/2026) : la note
    // se garde en base, donc seule la première composition d'un carnet la
    // paie. ⚠️ **Avant la lecture du carnet, et pas après** — c'est elle qui
    // charge les photos avec leur note, et une note écrite ensuite n'aurait
    // servi qu'à la composition suivante.
    await settlePhotoBeauty(context, found.memoId);

    const memo = await prisma.memo.findUniqueOrThrow({
      where: { id: found.memoId },
      include: {
        entries: {
          orderBy: { capturedAt: "asc" },
          include: {
            media: true,
            // **L'étape à laquelle le souvenir appartient** (T267) : son lieu
            // est le repli de l'en-tête quand le vocal n'en dit pas. Ce n'est
            // pas une déduction, c'est le lieu de cette étape-là.
            step: { select: { placeName: true, destinationName: true } },
          },
        },
        // Les deux plats du carnet lisent le voyage : les étapes et les pays
        // traversés font les chiffres du dos, les photos importées font les
        // couvertures (`services/bookCovers.ts`).
        // ⚠️ `orderBy` explicite : le pays de chaque étape sert à ouvrir les
        // chapitres sur leur carte (T284), et l'ordre fait alors foi.
        steps: {
          select: { destinationCountryCode: true, transport: true },
          orderBy: { number: "asc" },
        },
        coverPhotos: { select: { id: true, storageKey: true }, orderBy: { createdAt: "asc" } },
        // **La photo principale du voyage** (T270, l'étoile lime) : elle sert
        // de couverture quand l'atelier n'en a pas composé une.
        coverEntry: { select: { media: { select: { cdnUrl: true } } } },
      },
    });

    // **Chaque photo doit être lisible, et joignable, avant le rendu** : le
    // moteur de PDF la télécharge lui-même au moment de composer la page, et
    // il ne sait peindre ni un HEIC ni une adresse inventée — voir
    // `services/renderPhotos.ts`, qui porte les deux pannes muettes d'où
    // sortaient des carnets sans photos.
    // L'adresse de chaque photo, par souvenir : un sticker se pose sur
    // l'étape de la photo dont il sort, et c'est par cette adresse que
    // l'atelier la reconnaît.
    const adresseDeLaPhoto = new Map<string, string>();

    const structuringEntries: StructuringEntry[] = [];
    for (const entry of memo.entries) {
      // Ratio photo / texte à 0 % : « aucune photo dans tout le carnet ». Elles
      // sont écartées avant la composition, pour que le récit prenne leur
      // place au lieu d'y laisser des trous (`bookSettings.ts`).
      if (entry.kind === "photo" && !keepsPhotos(memo)) continue;
      let photoUrl: string | null = null;

      if (entry.kind === "photo" && entry.media) {
        photoUrl = await renderablePhotoUrl(context, entry.media);
        if (photoUrl) adresseDeLaPhoto.set(entry.id, photoUrl);
      }

      structuringEntries.push({
        kind: entry.kind,
        // `finalTextOf` fait la hiérarchie : correction manuelle, puis texte
        // rédigé, puis transcription brute en dernier recours (rédaction
        // échouée — mieux vaut un carnet au texte imparfait qu'un carnet vide).
        transcript: finalTextOf(entry),
        editedByUser: entry.editedText !== null,
        title: entry.suggestedTitle,
        // Le réglage « Insérer des Fun facts » de la personnalisation : coupé,
        // aucun encart n'entre au carnet. La rédaction les écrit quand même,
        // pour qu'un réglage rallumé les retrouve sans tout relancer.
        funFact: memo.funFactsEnabled ? entry.funFact : null,
        funFactTitle: memo.funFactsEnabled ? entry.funFactTitle : null,
        // Même chose pour « Quiz intégrés à l'histoire » : coupé, aucun quiz.
        quiz: memo.quizEnabled ? quizForBook(entry) : null,
        weatherKey: entry.weatherKey,
        capturedAt: entry.capturedAt,
        placeLabel: entry.placeLabel,
        // Le lieu de l'étape qui porte ce souvenir, quand il y en a une
        // (T267). `structuring.ts` s'en sert faute de mieux.
        stepPlace: entry.step?.placeName?.trim() || entry.step?.destinationName?.trim() || null,
        photoUrl,
        // Ce qu'on a mesuré de la photo à son arrivée (T265) : c'est ce qui
        // départage les photos d'une étape quand la page n'en dessine qu'une
        // partie. Nuls pour une photo d'avant le 18/11/2026.
        photoSharpness: entry.photoSharpness,
        photoVerdict: entry.photoVerdict,
        photoBeauty: entry.photoBeauty,
      });
    }

    // **Les stickers découpés dans les vraies photos** (Hugo, 10/11/2026) :
    // billets, tampons, étiquettes. **Après** la boucle ci-dessus, et c'est
    // voulu : c'est elle qui convertit en JPEG les photos que le moteur de PDF
    // ne sait pas peindre, HEIC d'iPhone en tête, et elle garde la conversion
    // en stockage. Les ciseaux travaillent donc sur des photos déjà lisibles,
    // sans les redécoder. Jamais bloquant : un sticker est une décoration,
    // voir `services/photoStickers.ts`.
    await settlePhotoStickers(context, memo.id);

    if (structuringEntries.length === 0) {
      throw new Error(
        "Ce carnet ne contient encore aucune entrée : enregistre au moins un souvenir avant de le générer.",
      );
    }

    // Un souvenir encore en cours de rédaction entrerait dans le PDF avec sa
    // transcription brute — hésitations comprises. Après trois minutes
    // d'attente, on renonce plutôt que de l'imprimer tel quel.
    const pending = memo.entries.filter(
      (entry) =>
        entry.kind !== "photo" &&
        (entry.redactionStatus === "pending" || entry.redactionStatus === "processing"),
    );

    if (pending.length > 0) {
      throw new Error(
        `${pending.length} souvenir(s) sont encore en cours de rédaction. ` +
          "Attends qu'ils soient prêts avant de générer le carnet.",
      );
    }

    const electedCoverUrl = (cdnUrl: string | null | undefined) =>
      cdnUrl && !isSimulatedCdnUrl(cdnUrl) ? cdnUrl : null;

    const compose = await structurer.structure({
      title: memo.title,
      subtitle: memo.subtitle,
      authors: memo.authors,
      theme: memo.theme,
      // La couverture composée dans l'atelier d'abord, la photo élue ensuite.
      // ⚠️ Une adresse de CDN **simulée** ne vaut rien ici : elle ne répond
      // pas, et la couverture arriverait vide (`services/webflow.ts`).
      coverPhotoUrl: memo.coverPhotoUrl ?? electedCoverUrl(memo.coverEntry?.media?.cdnUrl),
      entries: structuringEntries,
      tripContext: parseTripContext(memo.tripContext),
    });
    // Les réglages de personnalisation qui touchent le gabarit : pointillés,
    // décorations, et ce qui resterait de photos à 0 %.
    // Et la première étape s'ouvre sur une page de gauche.
    // Et le carnet tient dans sa cible de pages, à ± 5 pages, quand ses photos
    // le permettent : hors d'atteinte, le composeur ne force rien et le dit.
    // Les stickers découpés qui ont une photo **dans ce carnet-ci** : à 0 %
    // de photos, ou pour une photo écartée, le sticker n'a pas d'étape où se
    // poser et il reste au placard.
    const photoStickers = (await photoStickersOf(context, memo.id)).flatMap((sticker) => {
      const source = adresseDeLaPhoto.get(sticker.entryId);
      return source ? [{ ...sticker, source }] : [];
    });
    if (photoStickers.length > 0) {
      logger.info(
        { renderId, memoId: memo.id, stickers: photoStickers.map((s) => s.label) },
        "Stickers découpés dans les photos du voyage.",
      );
    }

    // **Un chapitre s'ouvre sur la carte de son pays** (T284) — avant
    // `applyBookSettings`, qui compose : c'est le champ `map` qui lui fait
    // choisir `layout_chapter_map` pour la première page de l'étape.
    const avecCartes = ouvrirLesChapitresSurUneCarte(
      compose,
      memo.steps.map((step) => step.destinationCountryCode),
      memo.destinationCountryCode,
    );

    // **Est-ce que cette photo illustre ce texte ?** (T265, le dernier tiers.)
    //
    // Après la mise en page, parce qu'il faut savoir quelle page montre quoi
    // pour n'interroger que les étapes qui **débordent** — celles dont la
    // page ne dessine pas toutes les photos. Une étape dont tout tient n'a
    // aucun choix à faire, et la faire juger serait payer pour rien.
    //
    // Contrairement à la beauté, cette note ne se garde pas : elle dépend du
    // couple photo-texte, et le texte change. Elle se refait donc à chaque
    // composition — d'où le soin à n'en demander que le strict nécessaire
    // (`docs/modeles-ia.md` § 2).
    const sourcesDesPhotos = new Map<string, PhotoSource>();
    for (const entry of memo.entries) {
      const url = adresseDeLaPhoto.get(entry.id);
      if (url && entry.media?.storageKey) {
        sourcesDesPhotos.set(url, { entryId: entry.id, storageKey: entry.media.storageKey });
      }
    }
    const joursComposes = (compose as unknown as { days?: unknown }).days;
    if (Array.isArray(joursComposes)) {
      const pertinence = await noterLaPertinence(
        context,
        joursComposes as Record<string, unknown>[],
        sourcesDesPhotos,
      );
      if (pertinence.size > 0) withBestPhotosFirst(compose, structuringEntries, pertinence);
    }

    const payload = premiereEtapeAGauche(
      applyBookSettings(
        avecCartes,
        memo,
        (texte) => {
          if (!texte.startsWith("pages cible")) return;
          if (texte.includes("hors d'atteinte")) logger.warn({ renderId, memoId: memo.id }, texte);
          else logger.info({ renderId, memoId: memo.id }, texte);
        },
        photoStickers,
      ),
    );

    // **Les deux plats que le voyageur a validés** (T259) : le gabarit dessine
    // le gabarit choisi, avec sa photo, ses mots et ses chiffres. Posés ici et
    // non par le composeur : une couverture n'est pas une page du carnet, elle
    // ne se recompose pas avec les étapes.
    //
    // La photo d'un plat se prépare d'abord, si la boucle ci-dessus ne l'a pas
    // déjà fait : à 0 % de photos, aucune n'est entrée au carnet, et la
    // couverture perdrait la sienne.
    for (const entryId of coverPhotoEntryIds(memo)) {
      if (adresseDeLaPhoto.has(entryId)) continue;
      const entry = memo.entries.find((candidate) => candidate.id === entryId);
      if (!entry?.media) continue;
      const url = await renderablePhotoUrl(context, entry.media);
      if (url) adresseDeLaPhoto.set(entryId, url);
    }

    payload["cover"] = bookCoversOf(
      context.env,
      memo,
      adresseDeLaPhoto,
      memo.entries.filter((entry) => entry.kind === "photo").length,
    );

    const validation = validatePayload(payload);
    if (!validation.valid) {
      const details = validation.errors
        .map((issue) => `${issue.path || "(racine)"}: ${issue.message}`)
        .join(" ; ");
      throw new Error(`Le carnet généré ne respecte pas le format attendu — ${details}`);
    }

    for (const warning of validation.warnings) {
      logger.warn({ renderId, ...warning }, "Écart aux bonnes pratiques éditoriales");
    }

    // **L'empreinte se pose ici, sur ce qui vient d'être composé** (T258,
    // Hugo 05/11/2026 : « ça mouline à nouveau même quand le carnet n'a subi
    // aucune modification »).
    //
    // Elle était posée par `ensureRenderInProgress`, *avant* que ce job ne
    // tourne — et les deux premières choses qu'il fait écrivent dans le
    // carnet : `refreshTripFactsQuietly` arrange les étapes et y rattache des
    // souvenirs, et la conversion des photos touche leurs médias. Le rendu
    // portait donc l'empreinte d'un état que sa propre exécution venait de
    // modifier : **il naissait périmé**, et chaque ouverture de l'aperçu
    // recomposait pour rien.
    //
    // Posée au moment où le `payload` est figé, elle répond à la vraie
    // question — « ce qu'il y a dans le carnet aujourd'hui est-il ce que ce
    // PDF montre ? » — et elle couvre tout ce que ce job a écrit lui-même.
    //
    // ⚠️ **Jamais plus tard que le payload.** Une écriture qui arriverait
    // entre les deux entrerait dans l'empreinte sans entrer dans le PDF : le
    // carnet se dirait à jour en montrant l'état d'avant, et on commanderait
    // un livre qui n'est plus le sien. Trop prudent fait attendre ; trop
    // confiant fait imprimer.
    const fingerprint = await currentBookFingerprint(prisma, memo.id);

    await prisma.render.update({
      where: { id: renderId },
      // `BookPayload` est un `Record<string, unknown>` : Prisma attend son
      // propre type d'entrée JSON, que la validation ci-dessus garantit.
      // `composingStartedAt` : la phase « composing » de l'aperçu commence.
      data: {
        payload: payload as Prisma.InputJsonObject,
        composingStartedAt: new Date(),
        inputFingerprint: fingerprint,
      },
    });

    await queue.publish<RenderJob>(JOB_NAMES.render, { renderId });
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    // **Pas de nouvel essai automatique** (07/10/2026) : pg-boss rejouait le
    // job trois fois, et un nouvel essai repassait le rendu de « échoué » à
    // « en cours » sous les yeux de l'aperçu — pendant que la prochaine
    // ouverture en lançait un autre, deux compositions payées pour une. C'est
    // désormais l'ouverture suivante de l'aperçu qui relance
    // (`ensureRenderInProgress`). Le journal garde l'erreur.
    logger.error({ err: cause, renderId }, "Mise en page du carnet échouée");
  }
}
