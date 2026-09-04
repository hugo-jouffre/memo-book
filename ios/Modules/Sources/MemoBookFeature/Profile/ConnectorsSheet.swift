import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Brancher MemoBook sur les apps qui savent déjà où tu es allé.
///
/// Chaque ligne est un **consentement** : le nom de l'app, ce que MemoBook fera
/// de l'accès, et l'interrupteur. La promesse est donc écrite en toutes lettres
/// à côté du geste qui l'accorde, jamais renvoyée à un écran de détail.
struct ConnectorsSheet: View {
    let model: ProfileModel

    var body: some View {
        BrandSheet(ConnectorsCopy.title, subtitle: ConnectorsCopy.promise) {
            VStack(spacing: MemoBookSpacing.s) {
                ForEach(model.profile?.connectors ?? []) { connector in
                    ConnectorCard(
                        connector: connector,
                        isEnabled: Binding(
                            get: { connector.isEnabled },
                            set: { model.setConnector(id: connector.id, isEnabled: $0) }
                        )
                    )
                }
            }
        }
    }
}

/// Une app tierce, sa promesse, son interrupteur.
private struct ConnectorCard: View {
    let connector: Connector
    @Binding var isEnabled: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Un `Toggle` porte l'ensemble : le libellé et la promesse deviennent
        // son étiquette, et VoiceOver lit « Strava, MemoBook pourra…, activé,
        // bouton interrupteur » d'un seul tenant.
        Toggle(isOn: $isEnabled) {
            content
        }
        .toggleStyle(.switch)
        .tint(MemoBookColor.action)
        .padding(MemoBookSpacing.s)
        .background(
            MemoBookColor.surface,
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(connector.name)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
            Text(connector.promise)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

        // En taille accessible, le logo passe au-dessus : lui garder sa colonne
        // laisserait à la promesse une largeur de deux mots.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                ConnectorLogo(connector: connector)
                text
            }
        } else {
            HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                ConnectorLogo(connector: connector)
                text
            }
        }
    }
}

/// Le logo d'une app tierce.
///
/// Ce sont des marques qui ne nous appartiennent pas : elles gardent leurs
/// couleurs — donc **pas** de `renderingMode(.template)` — et ne sont jamais
/// remplacées par une icône du jeu MemoBook, qui induirait en erreur. La
/// pastille à initiale reste le repli quand un connecteur arrive sans logo.
private struct ConnectorLogo: View {
    let connector: Connector

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.cornerRadius - 2)
    }

    var body: some View {
        Group {
            if let name = connector.logoAssetName {
                Image(brand: name)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(connector.name.prefix(1).uppercased())
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MemoBookColor.outline)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        // Un filet très clair : plusieurs de ces logos sont blancs sur blanc et
        // se dissoudraient dans la carte sans lui.
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

#Preview("Connecteurs") {
    let model = ProfileModel()

    return Color.clear
        .background(MemoBookColor.background)
        .task { await model.load() }
        .sheet(isPresented: .constant(true)) {
            ConnectorsSheet(model: model)
        }
}
