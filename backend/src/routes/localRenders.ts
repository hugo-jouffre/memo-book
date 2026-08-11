import { createReadStream, existsSync } from "node:fs";
import { resolve } from "node:path";
import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { LOCAL_RENDER_FILENAME } from "../services/localRenderer.js";

/**
 * Sert les PDF produits par `LocalChromiumRenderer`.
 *
 * Enregistrée uniquement quand `RENDERER=local`, c'est-à-dire sur une machine
 * de développement : elle existe parce que l'app iOS télécharge `pdfUrl` en
 * HTTP simple (`BookPreviewView.swift`), sans en-tête d'authentification.
 * Hors de ce mode, la route n'existe pas du tout.
 */
export function registerLocalRenderRoutes(app: FastifyInstance, context: AppContext): void {
  if (context.env.RENDERER !== "local") return;

  const directory = resolve(context.env.RENDER_OUTPUT_DIR);

  app.get("/v1/local-renders/:file", async (request, reply) => {
    const { file } = request.params as { file: string };

    // Le nom est entièrement contraint par la regex : aucun `..`, aucun `/`,
    // donc aucune traversée de répertoire possible.
    if (!LOCAL_RENDER_FILENAME.test(file)) {
      throw HttpError.notFound("Rendu introuvable.");
    }

    const path = resolve(directory, file);
    if (!existsSync(path)) {
      throw HttpError.notFound("Rendu introuvable.");
    }

    return reply.type("application/pdf").send(createReadStream(path));
  });
}
