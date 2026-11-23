import Foundation
import MemoBookCore

/// La campagne du bac à sable — celle qu'on regarde sans serveur.
///
/// Ses quatre questions sont les quatre formes que l'app sait dessiner : une
/// liste d'options, une note en étoiles, un curseur et un champ libre. Une
/// campagne de production n'a pas à leur ressembler — c'est tout l'intérêt,
/// elle s'écrit en base. Celle-ci les montre toutes pour qu'on puisse les
/// regarder sans serveur.
extension FeedbackCampaign {
    public static let fixture = FeedbackCampaign(
        id: "campagne-avis-v1",
        key: "avis-v1",
        title: "Comment ça se passe ?",
        subtitle: "Quatre questions, une minute. Ça nous aide beaucoup.",
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
                id: "question-note",
                kind: .rating,
                prompt: "Tes carnets, tu les trouves comment ?",
                scale: FeedbackQuestion.Scale(min: 1, max: 5, step: 1)
            ),
            FeedbackQuestion(
                id: "question-rythme",
                kind: .slider,
                prompt: "MEMO te relance…",
                scale: FeedbackQuestion.Scale(
                    min: 0,
                    max: 4,
                    step: 1,
                    ticks: ["Jamais", "Peu", "Bien", "Assez", "Trop"],
                    minLabel: "Pas assez",
                    maxLabel: "Trop souvent"
                )
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
