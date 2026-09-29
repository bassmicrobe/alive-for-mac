// Mac-only: reusable dark-catalog components (upstream draws these by hand in GDI+: Chrome.cs,
// Pill*.cs). Every interactive one has designed hover / pressed / focus / disabled states.
import SwiftUI

// MARK: - Focus ring

extension View {
    /// The ring shown around keyboard-focused controls.
    func focusRing(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.focus.opacity(isFocused ? 0.9 : 0), lineWidth: 2)
                .padding(-1)
                .allowsHitTesting(false)
        )
    }

    /// Row highlight on hover, as in the upstream lists.
    func rowHover(cornerRadius: CGFloat = Theme.rowPillH / 2) -> some View {
        modifier(RowHoverModifier(cornerRadius: cornerRadius))
    }
}

private struct RowHoverModifier: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? Theme.rowHover : .clear)
            )
            .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
    }
}

// MARK: - Pill button

enum PillKind {
    /// Quiet surface pill (Filters, secondary actions).
    case quiet
    /// Light gradient primary action ("Open in Live").
    case primary
}

struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .quiet

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(kind: kind, configuration: configuration)
    }

    private struct PillButtonBody: View {
        let kind: PillKind
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(Theme.fButton)
                .foregroundStyle(foreground)
                .padding(.horizontal, 16)
                .frame(minHeight: Theme.controlH)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(isDimmedPrimary ? Theme.hairline : Theme.cardBorder, lineWidth: 1))
                .focusRing(isFocused, cornerRadius: Theme.controlH / 2)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled || isDimmedPrimary ? 1 : 0.4)
                .animation(Theme.hoverAnimation, value: hovering)
                .animation(Theme.hoverAnimation, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        /// A disabled primary button turns into a dark, outlined pill with legible secondary text
        /// (fading the light gradient to 40 % left grey-on-grey text) — readable, yet plainly off.
        private var isDimmedPrimary: Bool { kind == .primary && !isEnabled }

        private var foreground: Color {
            if isDimmedPrimary { return Theme.secondaryText }
            return kind == .primary ? Theme.onLight : Theme.text
        }

        private var fill: AnyShapeStyle {
            if isDimmedPrimary { return AnyShapeStyle(Theme.surface) }
            switch kind {
            case .quiet:
                let color = configuration.isPressed ? Theme.surfacePressed
                    : hovering ? Theme.surfaceHover : Theme.surface
                return AnyShapeStyle(color)
            case .primary:
                let colors = configuration.isPressed
                    ? [Theme.lightPressed, Theme.lightPressed]
                    : hovering ? [Color.white, Theme.lightTop] : [Theme.lightTop, Theme.light]
                return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

struct PillButton: View {
    let title: String
    var icon: AppIcon?
    var kind: PillKind = .quiet
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { IconView(icon: icon, size: 12) }
                Text(title)
            }
        }
        .buttonStyle(PillButtonStyle(kind: kind))
    }
}

// MARK: - Circle icon button

struct CircleIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        CircleBody(isActive: isActive, configuration: configuration)
    }

    private struct CircleBody: View {
        let isActive: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isActive ? Theme.onLight : hovering ? Color.white : Theme.text)
                .frame(width: Theme.iconSize, height: Theme.iconSize)
                .background(fill, in: Circle())
                .overlay(Circle().strokeBorder(Theme.cardBorder, lineWidth: 1))
                .focusRing(isFocused, cornerRadius: Theme.iconSize / 2)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(Theme.hoverAnimation, value: hovering)
                .animation(Theme.hoverAnimation, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            if isActive { return Theme.light }
            return configuration.isPressed ? Theme.surfacePressed : hovering ? Theme.surfaceHover : Theme.surface
        }
    }
}

struct CircleIconButton: View {
    let icon: AppIcon
    let help: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { IconView(icon: icon) }
            .buttonStyle(CircleIconButtonStyle(isActive: isActive))
            .help(help)
            .accessibilityLabel(help)
    }
}

// MARK: - Pill tabs

struct PillTabItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

/// Segmented pill control: a surface capsule with a light selection capsule that glides between
/// the items.
struct PillTabs<Value: Hashable>: View {
    let items: [PillTabItem<Value>]
    @Binding var selection: Value
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                PillTab(title: item.title, isSelected: item.value == selection, namespace: selectionNamespace) {
                    withAnimation(Theme.selectAnimation) { selection = item.value }
                }
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

private struct PillTab: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.fButton)
                .foregroundStyle(isSelected ? Theme.onLight : hovering ? Color.white : Theme.secondaryText)
                .padding(.horizontal, 15)
                .frame(height: Theme.controlH - 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.lightTop, Theme.light],
                                                 startPoint: .top, endPoint: .bottom))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    } else if hovering {
                        Capsule().fill(Color.white.opacity(0.06))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(TabPressStyle())
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TabPressStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .focusRing(isFocused, cornerRadius: Theme.controlH / 2)
    }
}

// MARK: - Tag pill

struct TagPill: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(text)
            .font(Theme.fBadge)
            .foregroundStyle(tint ?? Theme.tagText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background((tint ?? Color.white).opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Cards, headers, empty states

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Theme.panelPad
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // Top-edge highlight: the glass card's inner light.
                Capsule().fill(Theme.cardHighlight).frame(height: 1).padding(.horizontal, Theme.cardR)
            }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title).font(Theme.fLabel).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct EmptyState: View {
    var icon: AppIcon = .nebula
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            IconView(icon: icon, size: 26, weight: .light)
                .foregroundStyle(Theme.secondaryText)
            Text(title).font(Theme.fHead).foregroundStyle(Theme.text)
            if let message {
                Text(message)
                    .font(Theme.fBody)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sheet frame

/// Common chrome for sheets: title row with a close button, content below.
struct SheetFrame<Content: View>: View {
    let title: String
    var width: CGFloat = 520
    var height: CGFloat?
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(Theme.fDialogTitle).foregroundStyle(Theme.text)
                Spacer()
                CircleIconButton(icon: .close, help: CommonStrings.close.s) { dismiss() }
            }
            content()
        }
        .padding(Theme.pad)
        .frame(width: width, height: height)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

/// The empty content every placeholder feature view shows until its implementer replaces it.
struct ComingSoonView: View {
    let title: String

    var body: some View {
        EmptyState(title: title, message: CommonStrings.comingSoonBody.s)
    }
}
