package com.memobook.networking

import com.memobook.core.Account
import com.memobook.core.AuthSession
import com.memobook.core.BookCoverEdit
import com.memobook.core.BookCovers
import com.memobook.core.BookCustomisationEdit
import com.memobook.core.BookPreview
import com.memobook.core.ChatPhotosTurn
import com.memobook.core.ChatTextTurn
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatVoiceTurn
import com.memobook.core.CoverPhoto
import com.memobook.core.CreatedTrip
import com.memobook.core.CustomerPaymentKey
import com.memobook.core.DataExportReceipt
import com.memobook.core.Entry
import com.memobook.core.EntryEdit
import com.memobook.core.EntryValidation
import com.memobook.core.FaqVote
import com.memobook.core.Gallery
import com.memobook.core.HomeFeed
import com.memobook.core.Memo
import com.memobook.core.MemoDetail
import com.memobook.core.MemoSummary
import com.memobook.core.NewMemo
import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.NewTextEntry
import com.memobook.core.OrderContext
import com.memobook.core.OrderQuote
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.ProfileEdit
import com.memobook.core.PushTokenRegistration
import com.memobook.core.Render
import com.memobook.core.ResumedOrderPayment
import com.memobook.core.ShippingSpeed
import com.memobook.core.Showcase
import com.memobook.core.SubscriptionCancellationReason
import com.memobook.core.SupportMessage
import com.memobook.core.TravelStatistics
import com.memobook.core.TravellerProfile
import com.memobook.core.TripDetail
import com.memobook.core.TripDraft
import com.memobook.core.TripSettings
import com.memobook.core.TripSettingsEdit
import com.memobook.core.TripTheme
import java.net.URI
import java.time.Instant

/**
 * Le contrat que les écrans connaissent. Le jumeau de
 * `MemoBookNetworking/MemoBookAPI.swift`.
 *
 * Les modèles d'écran en dépendent, pas de l'implémentation : c'est ce qui
 * permet de les piloter avec un double en test et dans les aperçus. Il n'y a
 * pas de couche `Repository` au-dessus, et c'est voulu — voir `ios/CLAUDE.md`.
 *
 * Chaque appel est `suspend` et **annulable** : quitter l'écran annule la
 * requête en vol. Les échecs sont des [ApiError].
 */
interface MemoBookApi {
    /** Enregistre l'appareil si nécessaire et mémorise son token. */
    suspend fun ensureDeviceRegistered()

    // region Compte

    /**
     * Une session est-elle déjà gardée ? Ne dit pas si elle est encore valide —
     * seul le serveur le sait, via [currentAccount].
     */
    suspend fun hasStoredSession(): Boolean

    suspend fun signUp(email: String, password: String, firstName: String?, lastName: String?): AuthSession

    suspend fun signIn(email: String, password: String): AuthSession

    /**
     * Échange un jeton d'identité Apple ou Google contre une session. Le
     * serveur vérifie le jeton auprès du fournisseur avant de répondre.
     */
    suspend fun signIn(with: SocialSignIn): AuthSession

    /**
     * Le compte de la session en cours. Sert aussi à savoir, au lancement, si
     * la session gardée vaut encore quelque chose.
     */
    suspend fun currentAccount(): Account

    /**
     * Ferme la session courante, et elle seule. Oublie le jeton local même si
     * le serveur est injoignable : l'utilisateur a demandé à sortir.
     */
    suspend fun signOut()

    /**
     * Demande l'e-mail qui permet de choisir un nouveau mot de passe.
     *
     * Sans session : c'est précisément parce qu'on ne peut pas entrer qu'on
     * l'appelle. Le serveur répond **la même chose** que l'adresse existe ou
     * non — on ne renseigne pas un inconnu sur qui a un compte —, si bien que
     * la réussite ici veut dire « si cette adresse est la tienne, regarde ta
     * boîte », jamais « ce compte existe ».
     */
    suspend fun requestPasswordReset(email: String)

    /**
     * Le nouveau mot de passe, avec le secret reçu par e-mail. Répond comme
     * [signIn] : la session est ouverte, l'app entre.
     */
    suspend fun resetPassword(token: String, password: String): AuthSession

    // endregion

    // region Les écrans
    //
    // Une réponse par écran, et non une par bloc : l'accueil et le profil
    // s'affichent d'un seul tenant, et les découper ferait apparaître leurs
    // morceaux les uns après les autres au lancement.

    /**
     * Tout ce qu'il faut pour dessiner l'accueil : le voyageur, ses voyages et
     * ceux où il est co-voyageur, la carte de découverte.
     */
    suspend fun homeFeed(): HomeFeed

    /** Un voyage ouvert : sa couverture, la relance et ses étapes. */
    suspend fun tripDetail(id: String): TripDetail

    /**
     * « Valider cette étape » : confirme l'étape et déclenche en fond une
     * nouvelle génération du carnet — sauf la première fois sur un mémo encore
     * vide. Idempotente : revalider une étape déjà validée ne fait rien de plus.
     * Rend le voyage entier, comme [tripDetail].
     */
    suspend fun validateStep(tripId: String, stepId: String): TripDetail

    /**
     * Crée un voyage à partir des six étapes de « Créer un voyage ». Rend le
     * voyage **et son code d'accès**, que la dernière étape affiche.
     */
    suspend fun createTrip(draft: TripDraft): CreatedTrip

    /**
     * Corrige un voyage avec les mêmes six champs. Sert à la flèche de retour
     * de la création : revenir sur les dates après avoir vu le code d'accès ne
     * doit pas créer un second voyage.
     */
    suspend fun updateTrip(id: String, draft: TripDraft): CreatedTrip

    /**
     * Rejoint le voyage de quelqu'un par son code d'accès — « Rejoins une
     * aventure ». Rend le voyage et son code, comme la création. Un code qui
     * ne mène nulle part lève [ApiError.Server] en 404, code `trip_not_found`.
     */
    suspend fun joinTrip(code: String): CreatedTrip

    /**
     * Les thèmes de « Contexte de ton voyage », dans l'ordre du serveur —
     * « Autre » en dernier. Une table de référence, pas une liste dans l'app.
     */
    suspend fun tripThemes(): List<TripTheme>

    /**
     * La galerie des carnets de la communauté : ses catégories, les carnets
     * publics, et le voyage que celui qui regarde peut reprendre.
     */
    suspend fun gallery(): Gallery

    /**
     * Les carnets mis en avant sur l'écran de bienvenue. Seul appel du contrat
     * qui ne demande **aucune** identification : cet écran s'affiche avant
     * l'entrée dans un compte.
     */
    suspend fun welcomeShowcases(): List<Showcase>

    suspend fun profile(): TravellerProfile

    /**
     * Les chiffres du profil — la feuille « Statistiques », réservée aux
     * abonnés. Additionnés par le serveur depuis les relevés de la rédaction ;
     * l'app les relit tant que `pendingDetections` n'est pas à zéro.
     */
    suspend fun travelStatistics(): TravelStatistics

    /**
     * Corrige le profil. Renvoie la version enregistrée par le serveur, qui
     * fait ensuite autorité sur ce que l'écran affiche.
     */
    suspend fun updateProfile(edit: ProfileEdit): TravellerProfile

    /**
     * Envoie la photo de profil — `POST /v1/profile/avatar`, en JPEG ou PNG.
     * Renvoie le profil relu, dont `avatarUrl` pointe désormais sur elle.
     */
    suspend fun uploadAvatar(data: ByteArray, mimeType: String): TravellerProfile

    /**
     * Retire la photo de profil — `DELETE /v1/profile/avatar`. Renvoie le
     * profil relu, sans `avatarUrl`.
     */
    suspend fun removeAvatar(): TravellerProfile

    /**
     * Change le mot de passe du compte — `POST /v1/profile/password`, avec
     * l'actuel pour preuve. Codes : `wrong_password`, `same_password`,
     * `no_password` (compte Apple ou Google). Les autres sessions du compte
     * sont fermées ; la sienne reste.
     */
    suspend fun changePassword(current: String, new: String)

    /**
     * Écrit à l'équipe — `POST /v1/support/messages` (T226). Ne rend rien
     * d'utile à l'écran : « envoyé » se dit **après** la réponse.
     * `429 support_rate_limited` au-delà de vingt messages en 24 h.
     */
    suspend fun sendSupportMessage(message: SupportMessage)

    /** « Est-ce utile ? » — `PUT /v1/support/faq-votes/:questionId`. Revoter remplace. */
    suspend fun voteOnFaq(questionId: String, isHelpful: Boolean, appVersion: String?)

    /**
     * Les votes déjà donnés par ce compte — `GET /v1/support/faq-votes` —,
     * pour remplacer les pouces par « Merci ! ».
     */
    suspend fun faqVotes(): List<FaqVote>

    /**
     * Résilie l'abonnement, au bout des trois confirmations de la feuille.
     *
     * Rend le profil relu : c'est lui qui porte l'abonnement fermé, la date de
     * résiliation et la période encore réglée. Le geste ne se devine pas côté
     * app — sans cet aller-retour, la résiliation ne survivait pas au
     * chargement suivant (Hugo, 19/09/2026).
     */
    suspend fun cancelSubscription(reason: SubscriptionCancellationReason?): TravellerProfile

    /**
     * Remet au serveur une transaction App Store — l'achat qui vient d'avoir
     * lieu, une restauration, ou ce que StoreKit rend au lancement.
     *
     * Le serveur vérifie la signature d'Apple et ouvre l'abonnement : c'est ce
     * qui laisse raconter dans la seconde, sans attendre la notification
     * d'Apple. `memoId` rattache l'achat au voyage qu'il finance. Rend le
     * profil relu, comme la résiliation.
     *
     * Porté pour la parité du contrat : l'app Android paie par Google Play
     * (`:payments`), et n'a pas de transaction App Store à remettre.
     */
    suspend fun syncAppStoreTransaction(signedTransaction: String, memoId: String?): TravellerProfile

    /** Branche ou débranche un connecteur. */
    suspend fun setConnector(key: String, isEnabled: Boolean)

    /**
     * Rattache l'appareil courant au compte connecté. À appeler juste après
     * une connexion.
     *
     * Il n'y a rien à transférer au passage : un carnet naît avec son
     * propriétaire, et l'appareil n'en possède aucun. Ce lien dit seulement sur
     * quelles installations le compte est ouvert.
     */
    suspend fun linkCurrentDevice()

    /**
     * Dit au serveur où joindre ce téléphone — `POST /v1/push-tokens`.
     *
     * À chaque entrée dans l'app, une fois l'autorisation donnée : le système
     * peut changer le jeton, et le fuseau suit le voyageur d'un pays à l'autre.
     * Le jeton est rattaché à **la session** : se déconnecter le fait oublier
     * au serveur, sans appel de plus.
     */
    suspend fun registerPushToken(registration: PushTokenRegistration)

    /**
     * On a touché une notification — `POST /v1/notifications/:id/opened`.
     * C'est le « comportement réel » qui ajuste le rythme des relances.
     */
    suspend fun markNotificationOpened(id: String)

    /**
     * Supprime le compte et **tout** ce qui est à lui : ses carnets, leurs
     * souvenirs et leurs médias, ses commandes, ses moyens de paiement, ses
     * connecteurs et ses appareils.
     *
     * Définitif et sans retour. **Un voyage partagé, lui, n'est pas supprimé :
     * il passe à son co-voyageur le plus ancien** — un récit écrit à plusieurs
     * ne s'efface pas parce que l'un s'en va. Seuls partent les voyages dont
     * personne d'autre ne fait partie. L'écran qui l'appelle doit avoir
     * demandé confirmation.
     */
    suspend fun deleteAccount()

    /**
     * « Exporter mes données » : le serveur envoie à l'adresse du compte le
     * lien d'une page où télécharger toutes ses données — RGPD, droit d'accès
     * et portabilité. Valable sept jours.
     *
     * Une seconde demande dans les cinq minutes n'envoie rien et le dit
     * (`alreadyRequested`). Codes : `no_email` (le compte n'a pas d'adresse),
     * `email_unavailable` (l'envoi a échoué, rien n'est parti).
     */
    suspend fun requestDataExport(): DataExportReceipt

    // endregion

    // region Carnets

    suspend fun memos(): List<MemoSummary>
    suspend fun createMemo(memo: NewMemo): Memo
    suspend fun memo(id: String): MemoDetail
    suspend fun deleteMemo(id: String)

    /**
     * `DELETE /v1/entries/:id` — efface un souvenir, pour tous les
     * co-voyageurs (T235). `204` sans corps ; `404` s'il n'existe plus.
     */
    suspend fun deleteEntry(id: String)

    suspend fun addTextEntry(memoId: String, entry: NewTextEntry): Entry

    /**
     * @param durationSeconds la durée **réellement capturée**, pauses déduites
     *   — voir `AudioRecorder.elapsed`. Elle part encore avec le fichier, mais
     *   **le serveur ne la croit plus** pour décompter le crédit du jour (Hugo,
     *   03/10/2026) : il mesure la durée dans le conteneur MPEG-4 lui-même
     *   (`lib/mp4Duration.ts`), et refuse un fichier illisible. Une durée
     *   déclarée se falsifie d'un champ de formulaire.
     */
    suspend fun uploadAudio(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        durationSeconds: Double?,
        placeLabel: String?,
    ): Entry

    suspend fun uploadPhoto(
        memoId: String,
        data: ByteArray,
        filename: String,
        mimeType: String,
        capturedAt: Instant,
        placeLabel: String?,
    ): Entry

    suspend fun entry(id: String): Entry

    /**
     * Corrige un souvenir à la main. Le texte corrigé fait ensuite autorité :
     * la mise en page le reprend au mot près.
     */
    suspend fun updateEntry(id: String, edit: EntryEdit): Entry

    /**
     * Redemande une rédaction — après un échec, ou quand le texte proposé ne
     * convient pas. Refusée si le souvenir a été corrigé à la main.
     */
    suspend fun retryRedaction(entryId: String): Entry

    // endregion

    // region La conversation avec MEMO — `docs/conversation.md`

    /**
     * Le fil d'un voyage. Le serveur y reconstruit d'abord les souvenirs
     * racontés hors du chat, pour qu'on les retrouve.
     */
    suspend fun chatThread(tripId: String): ChatThread

    /**
     * La suite du fil depuis un instant — le `now` de la lecture précédente,
     * en temps serveur. C'est ce que l'écran sonde tant qu'un tour est en vol.
     */
    suspend fun chatUpdates(tripId: String, since: Instant): ChatThreadUpdate

    /** Un texte ou une puce. Le serveur répond tout de suite ; MEMO, ensuite. */
    suspend fun sendChatText(tripId: String, turn: ChatTextTurn): ChatTurnReceipt

    /** Un vocal : le souvenir est créé, sa fiche posée, la transcription enfilée. */
    suspend fun sendChatVoice(tripId: String, turn: ChatVoiceTurn): ChatTurnReceipt

    /** Une à six photos : un souvenir par image, une seule bulle. */
    suspend fun sendChatPhotos(tripId: String, turn: ChatPhotosTurn): ChatTurnReceipt

    /** « Ça me convient » : le souvenir est relu et validé. */
    suspend fun validateEntry(id: String): EntryValidation

    /** « Supprimer la conversation » — propriétaire seul, garde l'ouverture. */
    suspend fun clearChat(tripId: String)

    /**
     * Le fichier d'un souvenir — un vocal à réécouter, une photo —, servi avec
     * la session : une URL nue ne suffirait pas.
     */
    suspend fun entryMedia(id: String): ByteArray

    /**
     * Le fichier d'un vocal du **contexte du voyage** : il n'est pas un
     * souvenir, son fichier pend au message (`/v1/chat-messages/:id/media`).
     */
    suspend fun chatMessageMedia(id: String): ByteArray

    /**
     * Lance la génération du carnet. Le résultat arrive de façon asynchrone :
     * suivre ensuite avec [render].
     */
    suspend fun startRender(memoId: String): Render
    suspend fun render(id: String): Render

    /**
     * Tout ce que le tunnel de commande a besoin de savoir pour s'ouvrir : la
     * carte du voyage, les prix, l'adresse proposée et les moyens de paiement.
     *
     * **Une réponse pour les sept étapes.** Le parcours est une seule
     * destination, et le découper ferait apparaître une attente à chaque
     * « Continuer ».
     */
    suspend fun orderContext(memoId: String): OrderContext

    /**
     * Le récapitulatif de l'étape 5, compté **par le serveur**. L'app
     * n'additionne aucun montant : deux calculs finissent par diverger, et
     * c'est le client qui a tort devant la personne qui paie.
     */
    suspend fun orderQuote(memoId: String, copies: Int, shippingSpeed: ShippingSpeed): OrderQuote

    /**
     * Accepte — ou refuse — d'être prévenu par WhatsApp de l'acheminement. Le
     * numéro remonte sur le compte quand celui-ci n'en a pas encore.
     */
    suspend fun setOrderWhatsApp(orderId: String, phone: String?): PrintOrder

    /**
     * L'aperçu du carnet : son statut de composition, le PDF une fois prêt, et
     * de quoi remplir la carte de partage. Pensée pour être interrogée en
     * boucle pendant la composition — la réponse est volontairement petite.
     */
    suspend fun bookPreview(memoId: String): BookPreview

    /**
     * Le lien public de prévisualisation du carnet, créé au premier appel et
     * rendu tel quel ensuite.
     *
     * **Idempotente côté serveur** : repartager deux fois ne donne pas deux
     * liens, et celui qu'on a envoyé hier marche encore aujourd'hui — un lien
     * parti dans une conversation ne se rattrape pas.
     */
    suspend fun bookShareLink(memoId: String): URI

    /**
     * Commande le carnet imprimé, sur un rendu déjà prévisualisé.
     *
     * **N'encaisse rien.** Elle enregistre la commande en brouillon et rend, à
     * côté, de quoi la régler — voir [PlacedPrintOrder]. Le passage en
     * `submitted` viendra du webhook de Stripe, jamais de l'app : entre le
     * moment où la feuille se ferme et celui où elle rappellerait le serveur,
     * l'app peut être tuée, et le paiement n'en aurait pas moins eu lieu.
     */
    suspend fun createPrintOrder(memoId: String, order: NewPrintOrderRequest): PlacedPrintOrder

    /**
     * Relit une commande, pour savoir ce que le serveur en dit **maintenant**.
     *
     * C'est la lecture qui suit un paiement : la feuille qui rend « réussi »
     * dit que Stripe a accepté, pas que notre serveur l'a appris.
     */
    suspend fun printOrder(id: String): PrintOrder

    suspend fun printOrders(memoId: String): List<PrintOrder>

    /**
     * Reprend le paiement d'une commande déjà passée, **sur la même
     * intention** — `POST /v1/orders/:id/payment`. « Payer » après une feuille
     * refermée créait une seconde commande. Une commande expirée répond 409
     * (`order_expired`).
     */
    suspend fun resumePrintOrderPayment(orderId: String, stripeApiVersion: String?): ResumedOrderPayment

    /** Abandonne une commande pas encore payée. Idempotente ; 409 si elle vient d'être payée. */
    suspend fun cancelPrintOrder(orderId: String): PrintOrder

    /**
     * Ce qui ouvre la feuille « Moyens de paiement » de Stripe — le client du
     * compte et une clé éphémère dans la version d'API du SDK.
     */
    suspend fun paymentMethodsKey(stripeApiVersion: String): CustomerPaymentKey

    /**
     * Une intention d'enregistrement de carte, demandée par la feuille « Moyens
     * de paiement » au moment où l'on en ajoute une.
     */
    suspend fun paymentMethodsSetupIntent(): String

    // endregion

    // region Les réglages d'un voyage

    /**
     * Les réglages d'un voyage : nom, dates, rythme, alertes, co-voyageurs,
     * code d'accès — **et les personnalisations du carnet**.
     *
     * Tout arrive en une réponse parce que l'écran les affiche ensemble : sept
     * appels feraient apparaître ses lignes une à une. Les personnalisations
     * voyagent avec, parce qu'il y en a un jeu par voyage et qu'aucune requête
     * ne les interroge seules.
     */
    suspend fun tripSettings(id: String): TripSettings

    /**
     * Les deux plats du carnet — `GET /v1/trips/:id/covers` : ce qu'on a
     * choisi, les styles, les photos du voyage et les chiffres du dos (T88).
     */
    suspend fun bookCovers(tripId: String): BookCovers

    /** Un geste sur un plat — `PATCH /v1/trips/:id/covers`. Rend les plats relus. */
    suspend fun updateBookCovers(tripId: String, edit: BookCoverEdit): BookCovers

    /**
     * Une photo importée pour la couverture — `POST /v1/trips/:id/covers/photos`,
     * en JPEG. Elle entre dans les photos du voyage ; la poser sur un plat est
     * un [updateBookCovers] de plus.
     */
    suspend fun uploadCoverPhoto(tripId: String, data: ByteArray): CoverPhoto

    /**
     * Change **un** réglage, et relit tout.
     *
     * Un à la fois, et non la structure entière : un co-voyageur peut régler le
     * même voyage au même moment, et renvoyer l'objet complet écraserait ce
     * qu'il vient de poser. La réponse est le voyage relu, ce que l'écran garde
     * à l'affichage.
     */
    suspend fun updateTripSettings(id: String, edit: TripSettingsEdit): TripSettings

    /** Change une personnalisation du carnet. Même route, même règle. */
    suspend fun updateBookCustomisation(tripId: String, edit: BookCustomisationEdit): TripSettings

    /**
     * Réécrit les étapes déjà écrites au nombre de pages cible actuel —
     * `POST /v1/trips/:id/page-target/rewrite`, sans corps. Le serveur répond
     * `202` avec les réglages relus et fait le travail en arrière-plan ; il
     * refuse (`409 page_target_rewrite_unavailable`) une seconde réécriture
     * pour le même changement.
     */
    suspend fun rewritePageTarget(tripId: String): TripSettings

    /**
     * Retire un co-voyageur du voyage, et relit les réglages.
     *
     * **Le propriétaire ne se retire pas** : le serveur refuse, et l'app ne le
     * propose pas. Les souvenirs de la personne retirée restent dans le carnet
     * — ils appartiennent au récit.
     */
    suspend fun removeCompanion(tripId: String, companionId: String): TripSettings

    /** Renvoie son lien d'invitation à quelqu'un qui n'est jamais entré. */
    suspend fun resendInvitation(tripId: String, companionId: String)

    // endregion
}
