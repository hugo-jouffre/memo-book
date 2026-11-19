import Foundation
import MemoBookCore

/// La campagne du bac à sable — celle qu'on regarde sans serveur.
///
/// Ses deux questions sont les deux formes que cette version sait dessiner :
/// une liste d'options et un champ libre. Une campagne de production n'a pas
/// à leur ressembler — c'est tout l'intérêt, elle s'écrit en base.
extension FeedbackCampaign {
    public static let fixture = FeedbackCampaign(
        id: "campagne-avis-v1",
        key: "avis-v1",
        title: "Comment ça se passe ?",
        subtitle: "Deux questions, trente secondes. Ça nous aide beaucoup.",
        submitLabel: "Envoyer",
        questions: [
            FeedbackQuestion(
                id: "question-usage",
                kind: .choice,
                prompt: "Tu racontes tes voyages…",
                isRequired: true,
                options: [
                    FeedbackQuestion.Option(key: "chaque-jour", label: "Chaque jour"),
                    FeedbackQuestion.Option(key: "de-temps-en-temps", label: "De temps en temps"),
                    FeedbackQuestion.Option(key: "au-retour", label: "Plutôt au retour"),
                ]
            ),
            FeedbackQuestion(
                id: "question-manque",
                kind: .text,
                prompt: "Qu'est-ce qui te manque ?",
                placeholder: "Dis-nous tout, même en deux mots."
            ),
        ]
    )
}
