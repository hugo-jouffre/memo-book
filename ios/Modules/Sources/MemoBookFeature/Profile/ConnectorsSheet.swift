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
/// ⚠️ **Les six logos ne sont pas encore dans le dépôt** : ils appartiennent à
/// leurs marques, et le quota MCP n'a pas permis de les exporter du nœud Figma.
/// En attendant, une pastille aux couleurs de MemoBook portant l'initiale — un
/// carré vide serait pire, et remplacer un logo de marque par une icône du jeu
/// MemoBook induirait en erreur.
private struct ConnectorLogo: View {
    let connector: Connector

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    var body: some View {
        Text(connector.name.prefix(1).uppercased())
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.ink)
            .frame(width: side, height: side)
            .background(
                MemoBookColor.outline,
                in: .rect(cornerRadius: MemoBookSpacing.cornerRadius - 2)
            )
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
