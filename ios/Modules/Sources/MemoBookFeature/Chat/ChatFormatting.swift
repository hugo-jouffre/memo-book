import Foundation
import MemoBookCore

// La mise en forme du chat : dates, durées, compteurs.
//
// À part de la vue, et par des `FormatStyle` plutôt que par concaténation —
// même parti pris que `TripFormatting` et `ProfileFormatting`. C'est le système
// qui sait écrire un jour de la semaine en français, et qui saura l'écrire dans
// une autre langue le jour où l'app y passe.

extension Date {
    /// « 26 août » — la date que porte une fiche de retranscription.
    ///
    /// Sans l'année : dans un fil de conversation, elle est presque toujours
    /// celle du jour, et l'écrire à chaque fiche mange la ligne pour rien. Voir
    /// ``chatFullDayLabel`` pour la version que lit VoiceOver.
    var chatDayLabel: String {
        formatted(.dateTime.day().month(.wide))
    }

    /// « mercredi 26 août 2026 » — ce que VoiceOver annonce.
    ///
    /// En toutes lettres et avec l'année, parce qu'une annonce vocale ne se
    /// relit pas : ce qui est ambigu à l'oreille est perdu.
    var chatFullDayLabel: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

extension TranscriptCard {
    /// **La date que la fiche affiche** : celle que le récit raconte, et `nil`
    /// quand il ne s'est pas situé (T308).
    ///
    /// Une journée donne « 28 août », une période « 28 – 30 août » : l'année
    /// n'y est pas, comme pour ``Date/chatDayLabel`` — dans un fil, elle est
    /// presque toujours celle du jour. Même règle de `FormatStyle` que
    /// ``Trip/dateRangeLabel``, qui écrit le mois une seule fois.
    ///
    /// `nil` n'est pas un trou à combler : la fiche n'affichait le jour de
    /// l'**enregistrement** que faute de mieux, et un dimanche imprimé sur une
    /// journée de vendredi est pire qu'une fiche sans date.
    var livedDatesLabel: String? {
        switch (livedFrom, livedTo) {
        case let (from?, to?) where from < to:
            (from..<to).formatted(.interval.day().month(.wide))
        case let (from?, _):
            from.chatDayLabel
        case (nil, _):
            nil
        }
    }

    /// La même chose pour VoiceOver : en toutes lettres, avec l'année — une
    /// annonce vocale ne se relit pas.
    var livedDatesSpokenLabel: String? {
        switch (livedFrom, livedTo) {
        case let (from?, to?) where from < to:
            (from..<to).formatted(.interval.weekday(.wide).day().month(.wide).year())
        case let (from?, _):
            from.chatFullDayLabel
        case (nil, _):
            nil
        }
    }
}

extension TimeInterval {
    /// « 0:37 » — la durée sous une forme d'onde.
    ///
    /// Le motif minute-seconde du système, et non un `String(format:)` : c'est
    /// lui qui décide de la place du séparateur, et il passe l'heure tout seul
    /// pour un vocal qui dépasserait les soixante minutes.
    var chatDurationLabel: String {
        Duration.seconds(max(0, rounded()))
            .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1)))
    }

    /// « 37 secondes » — ce que VoiceOver annonce. Un « 0:37 » lu à voix haute
    /// donne « zéro deux-points trente-sept ».
    var chatSpokenDurationLabel: String {
        Duration.seconds(max(0, rounded()))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}
