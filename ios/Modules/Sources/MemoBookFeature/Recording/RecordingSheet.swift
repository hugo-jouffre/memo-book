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
struct RecordingSheet: View {
    /// Le vocal, une fois terminé. La feuille ne l'envoie nulle part : elle le
    /// rend, et c'est l'écran qui l'a présentée qui décide de son sort.
    let onFinish: (RecordedAudio) -> Void

    @State private var model = RecordingModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(
            "Enregistrement",
            subtitle: "Enregistre tout ce que tu veux et MemoBook l’attribuera automatiquement",
            titleAlignment: .centered,
            surface: .listening
        ) {
            VStack(spacing: MemoBookSpacing.m) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                }

                RecordButton(
                    isRecording: model.isRecording,
                    isPaused: model.isPaused,
                    isBusy: model.isBusy,
                    level: model.level
                ) {
                    Task { await toggle() }
                }

                elapsed
                BrandWaveform(levels: model.levels, isDimmed: model.isPaused)
                transcript
                secondaryControls
            }
            .frame(maxWidth: .infinity)
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
        .task { await model.start() }
        // Quitter la feuille au glissé, c'est renoncer : le micro se referme et
        // rien n'est gardé. Sans ça, l'enregistrement continuait de tourner
        // derrière un écran qu'on croyait avoir fermé.
        .onDisappear { model.discard() }
    }

    private func toggle() async {
        guard let audio = await model.toggle() else { return }
        dismiss()
        onFinish(audio)
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

    /// Les mots, à mesure qu'ils sortent.
    ///
    /// Ils viennent de la reconnaissance vocale d'iOS et ne servent qu'à **se
    /// voir parler** — c'est le serveur qui transcrira le vocal pour de bon.
    /// D'où le gris : ce n'est pas encore du texte de carnet.
    ///
    /// Le bloc garde sa hauteur, pleine ou vide, et montre la **fin** du texte
    /// avec un « … » devant : on lit ce qu'on vient de dire, pas le début de
    /// l'enregistrement.
    private var transcript: some View {
        Text(model.transcript.isEmpty ? placeholder : model.transcript)
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)
            .truncationMode(.head)
            .frame(maxWidth: .infinity)
            .mask { readingMask }
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: model.transcript)
            .accessibilityLabel(model.transcript)
    }

    /// Ce qui estompe le texte transcrit — et **seulement** lui.
    ///
    /// Les mots ne s'arrêtent pas au bord du bloc : il y en avait avant, il y
    /// en aura après. Le dégradé éteint donc le **début** et la **fin** du
    /// texte, et laisse le milieu à pleine encre : on lit ce qui vient d'être
    /// dit, et on voit que ça continue des deux côtés.
    ///
    /// Il va en diagonale parce que le texte, lui, va en diagonale : son début
    /// est en haut à gauche, sa fin en bas à droite. Un dégradé vertical
    /// éteindrait des **lignes** entières, ce qui n'est pas la même idée.
    ///
    /// Rien de tout ça pour le texte d'attente : ce n'est pas un extrait, c'est
    /// une phrase entière qu'on doit pouvoir lire d'un bloc.
    @ViewBuilder
    private var readingMask: some View {
        if model.transcript.isEmpty {
            Color.black
        } else {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.2), location: 0),
                    .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7),
                    .init(color: .black.opacity(0.2), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Ce qui tient la place du texte tant qu'il n'y en a pas.
    ///
    /// Trois états, et **aucun ne promet de transcription** : la reconnaissance
    /// vocale a le droit d'être refusée ou indisponible, et une phrase du genre
    /// « MemoBook t'écoute » ferait alors passer une absence pour une panne. On
    /// dit ce que l'app fait — elle attend, elle enregistre, elle est en pause —
    /// et les mots arrivent en plus quand ils arrivent.
    private var placeholder: String {
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

#Preview("Enregistrement") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            RecordingSheet { _ in }
        }
}
