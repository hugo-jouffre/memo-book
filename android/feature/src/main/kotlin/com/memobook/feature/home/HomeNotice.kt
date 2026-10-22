package com.memobook.feature.home

/**
 * Ce que l'accueil a à dire sur la connexion et sur les vocaux en route.
 * Jumeau de `Home/HomeNotice.swift`.
 *
 * **Une seule boîte, quatre états.** Elle est toujours au même endroit — sous
 * la salutation, avant les voyages — et ne dit jamais qu'une chose à la fois :
 * une bande d'état qui s'empile finit par ne plus être lue. L'ordre de
 * priorité est celui de [HomeModel.notice], et il suit ce qui est le plus
 * utile à savoir : ce qui part maintenant, puis ce qui attend, puis ce qui
 * vient d'arriver, puis l'absence de réseau.
 *
 * Les messages sont ici et non dans la vue : ils dépendent d'un état, et un
 * état se teste.
 */
sealed interface HomeNotice {
    /**
     * Pas de réseau, et rien en attente : on prévient que l'app continue de
     * marcher, ce qui est l'information utile.
     */
    data object Offline : HomeNotice

    /** Des vocaux dorment sur le téléphone en attendant le réseau. */
    data class WaitingForConnection(val count: Int) : HomeNotice

    /** Des vocaux sont en train de partir. */
    data class Sending(val count: Int) : HomeNotice

    /**
     * Des vocaux viennent d'arriver. Transitoire — voir
     * `RecordingOutbox.justDelivered`.
     */
    data class Delivered(val count: Int) : HomeNotice

    /**
     * Le message, avec la partie qui compte entre `**` — voir `BrandNotice`.
     *
     * Le singulier n'est pas une coquetterie : « Tes 1 vocaux » est le genre
     * de phrase qui fait douter de tout le reste de l'app.
     */
    val message: String
        get() = when (this) {
            Offline ->
                "Tu sembles hors ligne. **Tu peux consulter tes récits et enregistrer des étapes**, qui seront retranscrites plus tard."

            // La file porte aussi les textes et les photos : un message qui ne
            // parlait que de « vocal » mentait après un texte (T170). Le texte
            // est celui de Hugo (06/10/2026), le même quel que soit le nombre.
            is WaitingForConnection ->
                "**Ta connexion internet est interrompue.** Mais ne t’inquiète pas, tes messages seront envoyés une fois la connexion rétablie. En attendant, tu peux envoyer autant de messages ou de photos que tu veux, ils seront enregistrés localement sur ton téléphone !"

            is Sending ->
                if (count <= 1) {
                    "**Ton vocal est en cours d’envoi.** Encore un instant."
                } else {
                    "**Tes $count vocaux sont en cours d’envoi.** Encore un instant."
                }

            is Delivered ->
                if (count <= 1) {
                    "**Ton vocal est bien arrivé.** Il sera retranscrit dans quelques instants."
                } else {
                    "**Tes $count vocaux sont bien arrivés.** Ils seront retranscrits dans quelques instants."
                }
        }

    /**
     * Le même message, débarrassé de son balisage : c'est ce que TalkBack
     * annonce quand la boîte change, et une annonce ne se lit pas deux fois.
     */
    val spokenMessage: String get() = message.replace("**", "")
}
