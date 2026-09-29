// Mac-only controls of the plugin filters sheet (upstream: PillToggle, TagField, FieldBox in
// PluginFiltersDialog.cs): a pill toggle with a count, a chip picker with a searchable popover,
// a wrapping layout for the chips.
import SwiftUI

/// A toggle pill: light when on, dimmed when it would match nothing (unless it is on).
struct FilterPill: View {
    let title: String
    var count: Int?
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Text(title)
                if let count { Text(String(count)).font(Theme.fBadge).opacity(0.6).monospacedDigit() }
            }
        }
        .buttonStyle(FilterPillStyle(isOn: isOn, isUseless: !isOn && count == 0))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct FilterPillStyle: ButtonStyle {
    let isOn: Bool
    let isUseless: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(isOn: isOn, isUseless: isUseless, configuration: configuration)
    }

    private struct Styled: View {
        let isOn: Bool
        let isUseless: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(Theme.fButton)
                .foregroundStyle(isOn ? Theme.onLight : Theme.text)
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.controlH)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
                .focusRing(isFocused, cornerRadius: Theme.controlH / 2)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isUseless ? 0.4 : 1)
                .animation(Theme.hoverAnimation, value: hovering)
                .animation(Theme.hoverAnimation, value: isOn)
                .onHover { hovering = $0 }
        }

        private var fill: AnyShapeStyle {
            if isOn {
                let colors = configuration.isPressed ? [Theme.lightPressed, Theme.lightPressed]
                    : hovering ? [Color.white, Theme.lightTop] : [Theme.lightTop, Theme.light]
                return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            }
            return AnyShapeStyle(configuration.isPressed ? Theme.surfacePressed
                                 : hovering ? Theme.surfaceHover : Theme.surface)
        }
    }
}

/// Selected values as removable chips and an "add" pill opening a searchable list.
struct ChipPicker: View {
    let placeholder: String
    let options: [String]
    @Binding var selection: Set<String>
    /// Whether picking the option could still match something.
    let isReachable: (String) -> Bool
    let label: (String) -> String
    @State private var open = false

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chosen, id: \.self) { value in
                Chip(text: label(value)) { selection.remove(value) }
            }
            if chosen.isEmpty {
                Text(placeholder).font(Theme.fBody).foregroundStyle(Theme.secondaryText).padding(.trailing, 4)
            }
            Button { open.toggle() } label: {
                IconView(icon: .plus, size: 11, weight: .bold)
            }
            .buttonStyle(CircleIconButtonStyle())
            .help(PluginsStrings.filterAdd.s)
            .accessibilityLabel("\(PluginsStrings.filterAdd.s): \(placeholder)")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                OptionList(options: options, selection: $selection, isReachable: isReachable, label: label)
            }
        }
    }

    private var chosen: [String] {
        options.filter { o in selection.contains { $0.caseInsensitiveCompare(o) == .orderedSame } }
    }
}

private struct Chip: View {
    let text: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(text).lineLimit(1)
                IconView(icon: .close, size: 9, weight: .bold)
                    .opacity(hovering ? 1 : 0.6)
            }
            .font(Theme.fLabel)
            .foregroundStyle(Theme.onLight)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(hovering ? Color.white : Theme.light, in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hoverAnimation, value: hovering)
        .accessibilityLabel(text)
        .help(CommonStrings.remove.s)
    }
}

private struct OptionList: View {
    let options: [String]
    @Binding var selection: Set<String>
    let isReachable: (String) -> Bool
    let label: (String) -> String
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            TextField(PluginsStrings.filterSearch.s, text: $query)
                .textFieldStyle(.plain)
                .font(Theme.fBody)
                .padding(.horizontal, 12)
                .frame(height: Theme.controlH)
                .background(Theme.sunken, in: Capsule())
                .focused($searchFocused)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible, id: \.self) { option in row(option) }
                    if visible.isEmpty {
                        Text(PluginsStrings.filterNothing.s)
                            .font(Theme.fLabel).foregroundStyle(Theme.secondaryText).padding(8)
                    }
                }
            }
            .frame(height: 240)
        }
        .padding(12)
        .frame(width: 260)
        .background(Theme.surface)
        .onAppear { searchFocused = true }
    }

    private var visible: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter {
            label($0).range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func row(_ option: String) -> some View {
        let on = selection.contains(option)
        let reachable = on || isReachable(option)
        return Button {
            if on { selection.remove(option) } else { selection.insert(option) }
        } label: {
            HStack {
                Text(label(option)).lineLimit(1)
                Spacer(minLength: 6)
                if on { IconView(icon: .check, size: 11, weight: .bold) }
            }
            .frame(minHeight: 26)
        }
        .buttonStyle(OptionRowStyle())
        .opacity(reachable ? 1 : 0.4)
        .disabled(!reachable)
    }
}

private struct OptionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.fBody)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(configuration.isPressed ? Theme.surfacePressed : hovering ? Theme.surfaceHover : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// A number field in a sunken capsule; empty means "no bound".
struct BoundField: View {
    let placeholder: String
    @Binding var value: Int?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Theme.fBody)
            .monospacedDigit()
            .padding(.horizontal, 14)
            .frame(width: 110, height: Theme.controlH)
            .background(Theme.sunken, in: Capsule())
            .focused($focused)
            .focusRing(focused, cornerRadius: Theme.controlH / 2)
    }

    /// Digits only; anything else is dropped as it is typed.
    private var text: Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { typed in
                let digits = typed.filter(\.isNumber)
                value = Int(digits.prefix(6))
            })
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
