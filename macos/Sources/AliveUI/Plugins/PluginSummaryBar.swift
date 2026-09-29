// Port of src/PluginSummary.cs: the cards above the list. A card is also a filter. Below them, one
// calm line says how many used plugins are not installed — or, when the machine's plugins could
// not be read at all, one notice instead of any per-plugin mark.
import SwiftUI
import AliveCore

struct PluginSummaryBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.plugins
        VStack(alignment: .leading, spacing: 10) {
            if model.inventoryAvailable {
                HStack(spacing: 10) {
                    ForEach(PluginCard.allCases) { card in
                        SummaryCard(card: card, health: model.health, isSelected: model.card == card) {
                            withAnimation(Theme.selectAnimation) { model.toggleCard(card) }
                        }
                    }
                }
                if model.missingUsedCount > 0 { MissingLine(count: model.missingUsedCount) }
            } else {
                UnavailableNotice()
            }
        }
    }
}

private struct SummaryCard: View {
    let card: PluginCard
    let health: PluginHealth
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(card.value(health)))
                    .font(Theme.fHead)
                    .monospacedDigit()
                    .foregroundStyle(tone)
                Text(PluginsFormat.card(card))
                    .font(Theme.fLabel)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(SummaryCardStyle(isSelected: isSelected))
        .accessibilityLabel("\(PluginsFormat.card(card)): \(card.value(health))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tone: Color {
        switch card.tone(health) {
        case .normal: return Theme.text
        case .good: return Theme.green
        case .bad: return Theme.red
        case .dim: return Theme.textDim
        }
    }
}

private struct SummaryCardStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(isSelected: isSelected, configuration: configuration)
    }

    private struct Styled: View {
        let isSelected: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
                        .strokeBorder(isSelected ? Theme.text.opacity(0.75) : Theme.cardBorder, lineWidth: 1)
                )
                .focusRing(isFocused, cornerRadius: Theme.cardR)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(Theme.hoverAnimation, value: hovering)
                .animation(Theme.hoverAnimation, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            if configuration.isPressed { return Theme.surfacePressed }
            if isSelected { return Theme.surfaceHover }
            return hovering ? Theme.surfaceHover : Theme.surface
        }
    }
}

/// "12 plugins used in your sets aren't installed" — one line, not one message per plugin.
private struct MissingLine: View {
    @Environment(AppModel.self) private var app
    let count: Int

    var body: some View {
        let showing = app.plugins.card == .missing
        HStack(spacing: 8) {
            Text(PluginsFormat.missingSummary(count))
                .font(Theme.fLabel)
                .foregroundStyle(Theme.textDim)
            Button(showing ? PluginsStrings.hideThem.s : PluginsStrings.showThem.s) {
                withAnimation(Theme.selectAnimation) {
                    app.plugins.card = showing ? nil : .missing
                }
            }
            .buttonStyle(LinkPillStyle())
        }
        .padding(.leading, 4)
    }
}

/// One calm notice when the installed plugins could not be read (never a red mark per plugin).
private struct UnavailableNotice: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                IconView(icon: .info, size: 16)
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(PluginsStrings.unavailableTitle.s)
                        .font(Theme.fTitle).foregroundStyle(Theme.text)
                    Text(PluginsStrings.unavailableBody.s)
                        .font(Theme.fLabel).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                PillButton(title: CommonStrings.rescan.s, icon: .refresh) { app.catalog.rescan() }
                PillButton(title: PluginsStrings.pluginSettings.s, icon: .settings) { openSettings() }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// A quiet text button: underlined on hover, brightened on press.
struct LinkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(Theme.fLabel)
                .foregroundStyle(configuration.isPressed ? Theme.lightPressed : hovering ? Theme.lightTop : Theme.light)
                .underline(hovering)
                .padding(.horizontal, 4)
                .focusRing(isFocused, cornerRadius: 6)
                .onHover { hovering = $0 }
        }
    }
}
