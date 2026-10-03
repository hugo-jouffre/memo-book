import Foundation
import MemoBookCore

extension ChatThread {
    /// Le fil qu'on ouvre **sans le serveur** : l'accueil de MEMO, et rien de
    /// ce qu'il a déjà dit.
    ///
    /// Deux cas, et les deux veulent qu'on puisse raconter quand même (Hugo,
    /// 01/10/2026) : un voyage créé hors ligne, que le serveur ne connaît pas
    /// encore ; et un voyage qu'on ouvre sans réseau. Ce qu'on y dit part dans
    /// la file et se pose en bulles « en cours d'envoi » — ``ChatModel`` les
    /// ajoute depuis ``ChatTransport/waiting``.
    ///
    /// **Pas une copie de l'ancien fil**, et c'est voulu : la conversation
    /// n'est pas gardée sur le téléphone, parce qu'un fil périmé se lit comme
    /// un message perdu (`ios/CLAUDE.md`, « Le cache local »). L'écran dit
    /// qu'il est hors ligne, et le vrai fil revient avec le réseau.
    ///
    /// **Le crédit du jour** suit le voyage tel que l'accueil l'a gardé
    /// (``Trip/dailyCredit``) : dans le métro, la barre continue de compter
    /// au lieu de laisser parler sans limite jusqu'à un refus. Passé sa
    /// recharge, il repart **plein** (``DailyCredit/refreshed(now:calendar:)``,
    /// 03/10/2026) plutôt que de ne plus rien dire : un fil ouvert le
    /// lendemain dans l'avion coupe toujours à la limite, au lieu de laisser
    /// dicter un vocal que le serveur refuserait chaque jour. Sans heure de
    /// recharge — un cache d'avant —, on ne sait pas de quel jour il est : il
    /// n'en dit rien.
    ///
    /// - Parameter isNew: le voyage vient d'être créé et n'a rien raconté. Il
    ///   s'ouvre alors comme le serveur l'ouvrirait, sur la puce du contexte —
    ///   celle qu'un carnet neuf propose en premier (`SUGGESTION_SETS.opening`
    ///   côté serveur). Sur un voyage déjà raconté, on ne sait pas où en est
    ///   la conversation : aucune puce, plutôt qu'une puce hors de propos.
    static func offline(trip: Trip, traveller: Traveller?, isNew: Bool) -> ChatThread {
        let initials = traveller?.firstName.first.map { String($0).uppercased() }

        return ChatThread(
            id: trip.id,
            title: trip.title,
            avatarUrl: trip.coverPhotoUrl,
            destination: trip.destination,
            greeting: ChatGreeting(
                title: trip.destination.map { ChatCopy.greetingTitle(place: $0.city ?? $0.name, flag: $0.flag) }
                    ?? ChatCopy.greetingTitleWithoutPlace,
                message: ChatCopy.greetingMessage
            ),
            context: ChatContext(
                tripId: trip.id,
                tripTitle: trip.title,
                travellerFirstName: traveller?.firstName,
                travellerInitials: initials,
                travellerAvatarUrl: traveller?.avatarUrl
            ),
            suggestions: isNew
                ? [
                    ChatSuggestion(
                        id: "context",
                        label: ChatCopy.Suggest.tellContext,
                        symbol: ChatCopy.Suggest.tellContextSymbol,
                        intent: .send
                    ),
                ]
                : [],
            // Personne ne peut effacer un fil qu'on ne tient pas.
            canClear: false,
            dailyCredit: trip.dailyCredit.flatMap { credit in
                guard credit.resetsAt != nil else { return nil }
                return credit.refreshed(now: .now)
            }
        )
    }
}
