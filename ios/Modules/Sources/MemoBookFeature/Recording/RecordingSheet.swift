import MemoBookCore
import MemoBookDesign
import MemoBookRecording
import SwiftUI

/// La feuille où l'on parle.
///
/// C'est **le** cœur du produit : tout ce que l'app sait faire commence ici.
/// D'où le bleu — voir ``MemoBookColor/listeningBackground`` : on quitte le
/// papier crème sur lequel on lit son carnet pour passer de l'autre côté, celui
/// où on le remplit.
///
/// **Rien à choisir avant de parler.** Pas de sélecteur de voyage, pas de titre
/// à saisir : on appuie, on raconte. C'est le sous-titre qui porte la promesse —
/// MemoBook rangera le souvenir tout seul.
///
/// Quatre commandes, et leurs rôles ne se recouvrent pas :
///
/// - le **disque** ouvre et referme le micro ;
/// - la **flèche circulaire** jette ce qui vient d'être dit et recommence ;
/// - les **deux barres** suspendent, pour reprendre son souffle ;
/// - le **rond de fermeture** de la feuille abandonne tout.
///
/// **Le crédit du jour du voyage en cours** (Hugo, 03/10/2026) : le bandeau
/// rouge doux se pose au-dessus du disque — à trente secondes de la limite,
/// puis il pulse, et l'enregistrement s'arrête net à zéro (le vocal part, et
/// la conversation s'ouvre dessus). Crédit déjà épuisé, le disque pâlit et le
/// bandeau « Crédit du jour épuisé » mène à l'offre — la feuille se referme
/// d'abord : une feuille ne s'empile pas sous un plein écran.
struct RecordingSheet: View {
    /// Le crédit du jour du voyage en cours, tel que l'accueil le tient.
    let credit: DailyCredit?

    /// Ce que fait le bandeau « épuisé » : ouvrir l'offre, **une fois la
    /// feuille refermée**.
    let onSubscribe: () -> Void

    /// Le vocal, une fois terminé, les niveaux relevés pendant qu'on parlait,
    /// et si c'est la limite du jour qui l'a coupé. La feuille ne l'envoie
    /// nulle part : elle le rend, et c'est l'écran qui l'a présentée qui
    /// décide de son sort — l'envoyer, et l'emporter dans la conversation
    /// (``RecordingHandoff``).
    let onFinish: (RecordedAudio, [Double], Bool) -> Void

    @State private var model: RecordingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le bandeau « épuisé » a été touché : l'offre s'ouvrira quand la feuille
    /// aura fini de descendre.
    @State private var opensOfferOnClose = false

    init(
        credit: DailyCredit? = nil,
        onSubscribe: @escaping () -> Void = {},
        onFinish: @escaping (RecordedAudio, [Double], Bool) -> Void
    ) {
        self.credit = credit
        self.onSubscribe = onSubscribe
        self.onFinish = onFinish
        _model = State(initialValue: RecordingModel(credit: credit))
    }

    var body: some View {
        BrandSheet(
            "Enregistrement",
            subtitle: RecordingCopy.subtitle(for: model.currentCredit),
            titleAlignment: .centered,
            surface: .listening
        ) {
            VStack(spacing: MemoBookSpacing.m) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                }

                // Au-dessus du disque, **dans la pile** : il se touche.
                if let banner = model.creditBanner {
                    DailyCreditBannerView(banner: banner, onSubscribe: openOffer)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                RecordButton(
                    isRecording: model.isRecording,
                    isPaused: model.isPaused,
                    isBusy: model.isBusy,
                    level: model.level
                ) {
                    Task { await toggle() }
                }
                // Pâli, pas désactivé : le toucher dit pourquoi rien ne s'ouvre.
                .opacity(model.isCreditExhausted ? 0.45 : 1)

                elapsed
                BrandWaveform(live: model.levels, isDimmed: model.isPaused)
                status
                secondaryControls
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: bannerState)
        }
        // **On appuie une fois, pas deux.** « Commencer à enregistrer » est déjà
        // la décision de parler : demander un second appui sur le disque faisait
        // perdre les premiers mots, ceux qu'on dit toujours pendant que la
        // feuille monte. Le micro s'ouvre donc avec elle, et le disque ne sert
        // plus qu'à s'arrêter.
        //
        // C'est aussi ici qu'apparaît la demande d'accès au micro, à la première
        // ouverture. `start()` ne fait rien si l'enregistrement tourne déjà :
        // rouvrir la feuille ne peut pas en lancer deux.
        .task {
            // L'arrêt net rend le vocal comme « Envoyer » : il part, et la
            // conversation s'ouvre dessus.
            model.onLimitReached = { audio, levels in
                dismiss()
                onFinish(audio, levels, true)
            }
            await model.start()
        }
        // Quitter la feuille au glissé, c'est renoncer : le micro se referme et
        // rien n'est gardé. Sans ça, l'enregistrement continuait de tourner
        // derrière un écran qu'on croyait avoir fermé.
        .onDisappear {
            model.discard()
            if opensOfferOnClose {
                opensOfferOnClose = false
                onSubscribe()
            }
        }
    }

    /// « Crédit du jour épuisé » touché : la feuille descend, puis l'offre
    /// monte en plein écran.
    private func openOffer() {
        opensOfferOnClose = true
        dismiss()
    }

    /// L'état du bandeau sans son chiffre — ce sur quoi il s'anime.
    private var bannerState: Int {
        switch model.creditBanner {
        case nil: 0
        case .warning: 1
        case .urgent: 2
        case .exhausted: 3
        }
    }

    /// Le geste du disque. Il ne referme la feuille que lorsqu'un vocal en
    /// sort : en pause, le disque reprend et la feuille reste.
    private func toggle() async {
        // Le relevé **entier**, et non la frise : `levels` ne garde que les
        // quarante dernières barres, celles qui défilent sous le micro. La
        // bulle du fil, elle, dessine tout le vocal — cadrée sur la frise, un
        // vocal de deux minutes aurait la silhouette de ses trois dernières
        // secondes.
        //
        // Et lu **avant** de refermer : la feuille l'efface en disparaissant
        // (`discard()`).
        let levels = model.capturedLevels
        guard let audio = await model.toggle() else { return }
        dismiss()
        onFinish(audio, levels, false)
    }

    /// Le chrono. Il n'apparaît qu'une fois qu'il y a quelque chose à compter :
    /// un « 0:00 » posé sous un bouton qu'on n'a pas encore touché n'annonce
    /// rien, il occupe.
    @ViewBuilder
    private var elapsed: some View {
        if model.isRecording {
            Text(model.elapsedLabel)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                // Les chiffres ne dansent pas : sans chasse fixe, la ligne
                // sautille à chaque seconde qui change de largeur.
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: model.elapsedLabel)
                .transition(.opacity)
                .accessibilityLabel("Durée : \(model.elapsedLabel)")
        }
    }

    /// Ce que l'app fait, dit en un mot sous la frise : elle attend, elle
    /// enregistre, elle est en pause.
    ///
    /// Il n'y a plus de mots transcrits à mesure qu'on parle : la
    /// reconnaissance vocale d'iOS faisait disparaître l'app sur l'iPhone de
    /// Hugo dès l'ouverture de la feuille, et la conversation prouve qu'on
    /// enregistre très bien sans elle (T176). C'est le serveur qui transcrit
    /// le vocal, une fois envoyé.
    private var status: some View {
        Text(statusLabel)
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: statusLabel)
    }

    private var statusLabel: String {
        if model.isPaused { return "En pause" }
        return model.isRecording ? "MemoBook enregistre" : "Prêt à enregistrer…"
    }

    /// Recommencer et suspendre. Les deux ne servent que pendant qu'on
    /// enregistre : au repos, ils n'auraient rien à annuler ni à suspendre.
    @ViewBuilder
    private var secondaryControls: some View {
        HStack {
            circularControl(
                systemImage: "arrow.counterclockwise",
                label: "Recommencer",
                isEnabled: model.isRecording
            ) {
                Task { await model.restart() }
            }

            Spacer(minLength: 0)

            circularControl(
                systemImage: model.isPaused ? "play.fill" : "pause.fill",
                label: model.isPaused ? "Reprendre" : "Mettre en pause",
                isEnabled: model.isRecording
            ) {
                model.togglePause()
            }
        }
        .padding(.horizontal, MemoBookSpacing.xs)
    }

    /// Une commande secondaire : un tracé nu, sans pastille ni cadre.
    ///
    /// Le symbole système et non le jeu de marque : ni la flèche circulaire ni
    /// la pause n'y existent, et les redessiner à la main donnerait deux tracés
    /// de plus à tenir. Même précédent que le calendrier et l'itinéraire de
    /// l'accueil ; un seul endroit à changer le jour où le jeu les gagne.
    private func circularControl(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isEnabled ? MemoBookColor.ink : MemoBookColor.ink.opacity(0.25))
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
        .accessibilityLabel(label)
    }
}

/// Les textes de la feuille qui dépendent du crédit du jour.
enum RecordingCopy {
    /// Le sous-titre. « Enregistre tout ce que tu veux » ne se dit plus qu'à
    /// un abonné : à un voyage qui a cinq minutes par jour, ce serait mentir
    /// (Hugo, 03/10/2026).
    ///
    /// **Pas de chiffre** pour qui a encore du crédit (03/10/2026) : lu à
    /// l'ouverture, il restait figé pendant que le bandeau, juste dessous,
    /// compte à rebours — et « Il te reste 3 min 20 aujourd’hui, et MemoBook
    /// l’attribuera » donnait à MemoBook le temps restant à ranger. C'est le
    /// bandeau qui dit ce qui reste, à trente secondes de la limite.
    static func subtitle(for credit: DailyCredit?) -> String {
        guard let credit else { return storyline }
        if credit.isUnlimited { return "Enregistre tout ce que tu veux et MemoBook l’attribuera automatiquement" }
        if credit.isExhausted { return "Ce voyage a raconté ses \(DailyCreditCopy.duration(credit.limitMs)) du jour" }
        return storyline
    }

    /// La promesse de la feuille : on raconte, MemoBook range — « l’ »
    /// reprend la journée qu'on raconte.
    static let storyline = "Raconte ta journée et MemoBook l’attribuera automatiquement"
}

#Preview("Enregistrement") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            RecordingSheet(credit: ChatCreditFixture.fresh) { _, _, _ in }
        }
}

#Preview("Enregistrement — crédit épuisé") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            RecordingSheet(credit: ChatCreditFixture.exhausted) { _, _, _ in }
        }
}

#Preview("Enregistrement — abonné") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            RecordingSheet(credit: ChatCreditFixture.unlimited) { _, _, _ in }
        }
}
