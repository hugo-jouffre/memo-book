import MemoBookDesign
import SwiftUI
import UserNotifications

/// **L'écran qui accompagne la question d'iOS sur les notifications**, à la
/// première ouverture de la conversation d'un voyage qu'on vient de créer
/// (Hugo, 03/11/2026 ; maquette « Améliorons MemoBook ensemble »).
///
/// Il ne dessine pas l'alerte — **c'est iOS qui la pose**, par-dessus, et lui
/// seul peut le faire : « "MemoBook" aimerait vous envoyer des
/// notifications ». L'écran, lui, tient le fond pendant ce temps-là : le titre
/// au-dessus de l'alerte, la flèche qui la désigne, et sous elle les deux
/// phrases qui disent à quoi sert la réponse. C'est un **contexte**, pas une
/// étape : il n'a ni bouton ni sortie, il s'efface dès qu'iOS a sa réponse.
///
/// **Il ne se montre qu'à qui n'a jamais répondu.** iOS ne pose la question
/// qu'une fois dans la vie de l'app, et l'étape « Notifications » de la
/// création d'un voyage la pose déjà quand on y choisit un rythme — voir
/// `docs/notifications.md`. Cet écran est le **recours** de qui a passé cette
/// étape : il arrive à la première conversation du voyage créé, là où la
/// promesse des relances se comprend enfin. Qui a déjà autorisé ou refusé ne
/// le voit jamais — il n'aurait porté aucune alerte.
///
/// La suite appartient à ``ChatNotificationsNudge`` : un refus, ou une
/// question restée sans réponse, revient en bulle dans le fil.
struct ChatNotificationsPrimer: View {
    /// iOS a répondu : l'écran s'efface, et la conversation relit
    /// l'autorisation.
    let onAnswered: () async -> Void

    /// Poser la question à iOS. Seuls les aperçus disent `false` : la question
    /// se pose toute seule ici, et un aperçu ne doit pas ouvrir d'alerte
    /// système — il reste donc sur l'écran, ce qui est justement ce qu'on
    /// vient y regarder.
    var asksSystem = true

    /// Qui pose la question — `nil` dans un aperçu, où aucune alerte système
    /// ne doit s'ouvrir.
    @Environment(\.pushNotifications) private var pushNotifications

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // **Aux tailles de texte accessibles, l'écran défile** : le titre et
        // les deux phrases ne tiennent plus entre l'en-tête et la barre
        // d'envoi, et un texte coupé par le bord vaut moins qu'un texte qu'on
        // fait glisser.
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView { column }.scrollIndicators(.hidden)
            } else {
                column.frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque : le fil est derrière, et la maquette ne le montre pas. Le
        // crème seul, sans le motif de marque — celui de l'écran continue en
        // dessous, le redessiner ici le décalerait.
        .background(MemoBookColor.background)
        .accessibilityElement(children: .combine)
        .task { await ask() }
    }

    private var column: some View {
        VStack(spacing: MemoBookSpacing.m) {
            Text(NotificationsPrimer.title)
                .font(MemoBookFont.h1)
                .foregroundStyle(MemoBookColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // La place de l'alerte d'iOS : l'écran la laisse vide, c'est le
            // système qui la remplit. Aucun vide à distribuer dans une vue qui
            // défile — le bloc du bas suit alors le titre.
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: MemoBookSpacing.m)
            }

            // La flèche et les phrases sont **un bloc**, serré : il doit tenir
            // sous l'alerte du système, qui occupe le milieu de l'écran.
            VStack(spacing: MemoBookSpacing.xs) {
                // Elle désigne l'alerte, elle ne dit rien de plus : aux tailles
                // de texte accessibles, c'est la place des phrases qu'elle
                // prendrait.
                if !typeSize.isAccessibilitySize {
                    PrimerArrow()
                        .stroke(MemoBookColor.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 40, height: 44)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, MemoBookSpacing.xl)
                        .accessibilityHidden(true)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    ForEach(NotificationsPrimer.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        // Le bas est plus serré que le haut : la flèche et les phrases
        // doivent passer **sous** l'alerte du système.
        .padding(.top, MemoBookSpacing.l)
        .padding(.bottom, MemoBookSpacing.xs)
        .frame(maxWidth: .infinity)
    }

    /// Pose la question d'iOS, puis s'efface.
    ///
    /// **Après que l'écran est dessiné**, et non pendant : l'alerte doit
    /// arriver *sur* lui, pas à sa place — c'est tout ce que cet écran a à
    /// faire.
    ///
    /// Dans le bac à sable, ``PushNotifications`` n'est pas branché (`nil`) :
    /// la question se pose alors directement au système, pour que l'écran se
    /// vérifie quand même — comme ``ChatNotificationsNudge``.
    private func ask() async {
        guard asksSystem else { return }
        try? await Task.sleep(for: NotificationsPrimer.settleBeforeAsking)
        if let pushNotifications {
            await pushNotifications.requestAuthorization()
        } else {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        await onAnswered()
    }
}

/// La flèche dessinée de la maquette : elle part d'en bas à droite, remonte et
/// se recourbe vers l'alerte, en haut à gauche.
///
/// Un tracé et non un asset : le jeu de marque n'a pas de flèche courbe, et
/// celle-ci n'existe que sur cet écran.
private struct PrimerArrow: Shape {
    /// La longueur des deux barbes de la pointe, en part de la hauteur.
    private static let barb: CGFloat = 0.34

    /// Leur écart de part et d'autre du tracé, en radians.
    private static let barbSpread = Double.pi * 32 / 180

    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: rect.minX, y: rect.minY)
        let tail = CGPoint(x: rect.maxX, y: rect.maxY)
        // Le point de contrôle, haut et à droite : la courbe part vers le bas
        // à droite, puis se redresse et arrive sur la pointe en diagonale,
        // comme sur la maquette. Plus bas, elle couchait la pointe à
        // l'horizontale et la flèche ne désignait plus l'alerte.
        let control = CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.52)

        var path = Path()
        path.move(to: tail)
        path.addQuadCurve(to: tip, control: control)

        // La pointe suit la tangente de la courbe — control → tip —, pour que
        // les barbes restent dans l'axe quelle que soit la taille du cadre.
        let heading = Double(atan2(tip.y - control.y, tip.x - control.x))
        let length = rect.height * Self.barb
        for side in [1.0, -1.0] {
            let direction = heading + .pi + side * Self.barbSpread
            path.move(to: tip)
            path.addLine(
                to: CGPoint(
                    x: tip.x + CGFloat(cos(direction)) * length,
                    y: tip.y + CGFloat(sin(direction)) * length
                )
            )
        }
        return path
    }
}

/// Ce que l'écran retient et ce qu'il dit — logique pure, testée.
///
/// La mémoire tient en **une** liste : les voyages créés sur cet appareil dont
/// la conversation n'a pas encore été ouverte. Créer un voyage y ajoute son
/// identifiant, l'ouvrir l'en retire — elle se vide donc toute seule, et il
/// n'y a pas de seconde liste à tenir d'accord avec la première.
enum NotificationsPrimer {
    /// Les voyages créés ici qui attendent leur première conversation.
    private static let awaitingKey = "memobook.notifications.primer.awaitingTrips"

    /// Le temps qu'on laisse à l'écran pour se poser avant que l'alerte d'iOS
    /// n'arrive dessus.
    static let settleBeforeAsking: Duration = .milliseconds(350)

    /// Un voyage vient d'être créé sur cet appareil.
    ///
    /// `nonisolated` : l'app l'appelle depuis la fonction d'enregistrement du
    /// brouillon, qui ne vit pas sur l'acteur principal.
    nonisolated static func markTripCreated(_ tripId: String, defaults: UserDefaults = .standard) {
        var awaiting = awaitingTrips(defaults: defaults)
        guard !awaiting.contains(tripId) else { return }
        awaiting.append(tripId)
        defaults.set(awaiting, forKey: awaitingKey)
    }

    /// La conversation de ce voyage s'ouvre : rend `true` si c'est la première
    /// fois, pour un voyage créé ici — et l'oublie, pour que la fois suivante
    /// n'en soit plus une.
    @discardableResult
    static func consumeFirstOpening(of tripId: String, defaults: UserDefaults = .standard) -> Bool {
        var awaiting = awaitingTrips(defaults: defaults)
        guard let index = awaiting.firstIndex(of: tripId) else { return false }
        awaiting.remove(at: index)
        defaults.set(awaiting, forKey: awaitingKey)
        return true
    }

    private nonisolated static func awaitingTrips(defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: awaitingKey) ?? []
    }

    /// L'écran se montre à la première conversation d'un voyage créé ici,
    /// **et seulement si la question n'a jamais été posée** : iOS ne la repose
    /// jamais, et un écran qui ne porterait aucune alerte ne dirait rien.
    static func isShown(isFirstOpeningOfANewTrip: Bool, authorization: UNAuthorizationStatus) -> Bool {
        isFirstOpeningOfANewTrip && authorization == .notDetermined
    }

    // MARK: - Les mots

    /// Le titre de la maquette, mot pour mot.
    static let title = "Améliorons MemoBook ensemble"

    /// Les deux phrases sous l'alerte. La seconde est celle de la maquette ; la
    /// première y parlait de savoir comment on nous a découverts — ce que cet
    /// écran ne demande pas. Elle dit donc ce que la réponse change vraiment.
    static let paragraphs = [
        "On s’en sert uniquement pour te faire signe quand il est temps de raconter la suite.",
        "Le contenu de ton carnet de voyage reste privé et nous n’allons jamais revendre tes données.",
    ]
}

#Preview("Notifications — l'écran de la question") {
    ChatNotificationsPrimer(onAnswered: {}, asksSystem: false)
        .environment(\.colorScheme, .light)
}

#Preview("Notifications — AX3") {
    ChatNotificationsPrimer(onAnswered: {}, asksSystem: false)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}
