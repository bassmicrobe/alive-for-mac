// Port of the controls of src/FiltersDialog.cs (FieldBox, TagField, PillToggle) in SwiftUI.
import SwiftUI
import AliveCore

/// A pill that toggles a condition on or off; greyed when picking it would leave nothing.
struct FilterToggle: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                if isOn { IconView(icon: .check, size: 9, weight: .bold) }
                Text(title)
            }
        }
        .buttonStyle(SetsFilterPillStyle(isOn: isOn))
        .disabled(!isEnabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Hover, pressed and keyboard-focus states of a filter pill (also the "show all" pill).
struct SetsFilterPillStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillBody(isOn: isOn, configuration: configuration)
    }

    private struct PillBody: View {
        let isOn: Bool
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(Theme.fSmall)
                .foregroundStyle(isOn ? Theme.onLight : hovering || configuration.isPressed ? Theme.text : Theme.secondaryText)
                .padding(.horizontal, 13)
                .frame(height: 26)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
                .focusRing(isFocused, cornerRadius: 13)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 }
                .animation(Theme.hoverAnimation, value: hovering)
                .animation(Theme.hoverAnimation, value: configuration.isPressed)
        }

        private var fill: AnyShapeStyle {
            if isOn { return AnyShapeStyle(configuration.isPressed ? Theme.lightPressed : Theme.light) }
            return AnyShapeStyle(configuration.isPressed ? Theme.surfacePressed : hovering ? Theme.surfaceHover : Theme.surface)
        }
    }
}

/// A multi-choice field: every value that occurs is a pill, the picked ones light up, the ones
/// that would leave no sets are greyed (they stay clickable when picked, to be undone).
/// With `collapsedLimit`, a long list shows that many pills (the picked ones always) and a
/// "Show all N" pill.
struct ChoicePills<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: [Value]
    var disabled: Set<Value> = []
    let placeholder: String
    var collapsedLimit: Int?
    @State private var showsAll = false

    var body: some View {
        if options.isEmpty {
            Text(placeholder).font(Theme.fSmall).foregroundStyle(Theme.secondaryText).frame(height: 26)
        } else {
            SetsFlowLayout(spacing: 6) {
                ForEach(visibleOptions) { option in
                    let picked = selection.contains(option.value)
                    FilterToggle(title: option.title,
                                 isOn: Binding(get: { picked }, set: { toggle(option.value, on: $0) }),
                                 isEnabled: picked || !disabled.contains(option.value))
                }
                if let limit = collapsedLimit, options.count > limit {
                    Button { showsAll.toggle() } label: {
                        Text(showsAll ? SetsStrings.fltShowFewer.s : SetsStrings.fltShowAll.f(options.count))
                    }
                    .buttonStyle(SetsFilterPillStyle(isOn: false))
                }
            }
        }
    }

    private var visibleOptions: [Option] {
        guard let limit = collapsedLimit, !showsAll, options.count > limit else { return options }
        return options.enumerated().filter { $0.offset < limit || selection.contains($0.element.value) }.map(\.element)
    }

    private func toggle(_ value: Value, on: Bool) {
        if on { if !selection.contains(value) { selection.append(value) } }
        else { selection.removeAll { $0 == value } }
    }
}

/// A sunken pill text field with a cue and an optional trailing icon button.
struct FilterField: View {
    let cue: String
    @Binding var text: String
    var isInvalid = false
    var leadingIcon: AppIcon?
    var onLeadingIcon: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                Button { onLeadingIcon?() } label: {
                    IconView(icon: leadingIcon, size: 12).foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help(SetsStrings.pickDate.s)
                .accessibilityLabel(SetsStrings.pickDate.s)
            }
            TextField("", text: $text, prompt: Text(cue).foregroundStyle(Theme.secondaryText))
                .textFieldStyle(.plain)
                .font(Theme.fBody)
                .foregroundStyle(isInvalid ? Theme.red : Theme.text)
                .focused($focused)
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.controlH)
        .background(Theme.sunken, in: Capsule())
        .overlay(Capsule().strokeBorder(isInvalid ? Theme.red.opacity(0.7) : Color.clear, lineWidth: 1))
        .focusRing(focused, cornerRadius: Theme.controlH / 2)
    }
}

/// A date text field whose calendar icon opens a picker; typed text is parsed leniently
/// ("2026", "2026-08", "2026-08-07") by `SetFilter.parseDate`.
struct DateFilterField: View {
    let cue: String
    let upperBound: Bool
    @Binding var date: Date?
    @State private var text = ""
    @State private var showPicker = false
    @State private var picked = Date()

    var body: some View {
        FilterField(cue: cue, text: $text, isInvalid: !text.isEmpty && SetFilter.parseDate(text, upperBound: upperBound) == nil,
                    leadingIcon: .calendar, onLeadingIcon: { picked = date ?? Date(); showPicker = true })
            .onAppear { text = SetFilter.formatDate(date) }
            .onChange(of: text) { _, new in
                date = SetFilter.parseDate(new, upperBound: upperBound)
            }
            .onChange(of: date) { _, new in
                // Follow resets from outside without fighting what is being typed.
                if new == nil, SetFilter.parseDate(text, upperBound: upperBound) != nil { text = "" }
            }
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                DatePicker("", selection: $picked, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .onChange(of: picked) { _, new in
                        text = SetFilter.formatDate(new)
                        showPicker = false
                    }
            }
    }
}

/// A count field: empty or junk means "no limit".
struct CountFilterField: View {
    let cue: String
    @Binding var value: Int
    @State private var text = ""

    var body: some View {
        FilterField(cue: cue, text: $text)
            .onAppear { text = SetFilter.formatCount(value) }
            .onChange(of: text) { _, new in value = SetFilter.parseCount(new) }
            .onChange(of: value) { _, new in
                if new < 0, SetFilter.parseCount(text) >= 0 { text = "" }
            }
    }
}
