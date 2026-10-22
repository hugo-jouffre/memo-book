package com.memobook.feature.bookpreview

import com.memobook.feature.AppDependencies
import java.io.File

/**
 * L'aperçu du carnet, branché sur le serveur — la fabrique
 * `bookPreviewModel(memoId:)` d'`AppDependencies.swift` :
 * `POST /v1/memos/:id/renders` pour lancer la composition à l'ouverture
 * (06/10/2026, T224), `GET /v1/memos/:id/preview` pour la suivre,
 * `GET /v1/trips/:id/covers` pour les deux plats de la première et de la
 * dernière page (T223), `POST /v1/memos/:id/share-link` pour le lien de
 * partage.
 *
 * Le bac à sable (`previewSignedIn`) répond par `PreviewApi` : son carnet est
 * déjà composé, et l'interrupteur `composeBook` y joue une composition d'une
 * dizaine de secondes — la file, la mise en page, le PDF — avant le carnet.
 *
 * Deux paramètres de plus qu'iOS, qui tiennent à Android :
 *
 * @param cacheDirectory le cache de l'app (`Context.cacheDir`), où le PDF
 *   s'écrit pour `PdfRenderer` et pour la feuille de partage. Ce n'est jamais
 *   `ContentCache` : ce sont des fichiers de travail, pas du contenu à relire
 *   hors ligne. `AppDependencies` ne garde pas le dossier qu'il reçoit, d'où ce
 *   paramètre ; il disparaît le jour où elle le garde.
 * @param opensBlankPages le `#if DEBUG` d'iOS : un build débogable ouvre
 *   l'aperçu sur des pages blanches quand rien n'a été composé.
 */
fun AppDependencies.bookPreviewModel(memoId: String, cacheDirectory: File, opensBlankPages: Boolean): BookPreviewModel =
    BookPreviewModel(
        memoId = memoId,
        source = { id -> api.bookPreview(memoId = id) },
        // Le rendu que le serveur rend — en cours, à jour ou neuf — ne sert à
        // rien ici : c'est le sondage de l'aperçu qui dit où il en est.
        startComposition = { id -> api.startRender(memoId = id) },
        covers = { id -> api.bookCovers(tripId = id) },
        requestLink = { id -> api.bookShareLink(memoId = id).toString() },
        documents = cacheDirectory,
        opensBlankPages = opensBlankPages,
    )
