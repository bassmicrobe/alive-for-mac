// Port of src/RescueDialog.cs (PluginCheckList row). A tick stands where it does in Live itself on
// an enabled device — it says "carries on working". Untick it and the plugin is off in the probe,
// and the row dims the way Live dims a disabled device.
import AliveCore
import SwiftUI

struct PluginCheckRow: View {
    let slot: AlsPluginSlot
    let isOn: Bool
    let note: RescueModel.RowNote?
    var isEnabled = true
    let toggle: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            CheckMark(isOn: isOn, isEnabled: isEnabled)
            Text(slot.format)
                .font(Theme.fBadge)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 40, alignment: .leading)
            Text(label)
                .font(Theme.fBody)
                .foregroundStyle(isOn ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if !slot.vendor.isEmpty {
                Text(slot.vendor)
                    .font(Theme.fSmall)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            if let note {
                Text(note == .breaksTheSet ? RescueStrings.noteBreaks.s : RescueStrings.noteSuspect.s)
                    .font(Theme.fBadge)
                    .foregroundStyle(note == .breaksTheSet ? Theme.errorText : Theme.secondaryText)
                    .frame(minWidth: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering && isEnabled ? Theme.rowHover : .clear)
        )
        .focusRing(focused && isEnabled, cornerRadius: 8)
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { toggle() } }
        .onHover { inside in withAnimation(Theme.hoverAnimation) { hovering = inside } }
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { isEnabled ? { toggle(); return .handled }() : .ignored }
        .onKeyPress(.return) { isEnabled ? { toggle(); return .handled }() : .ignored }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? CommonStrings.stateOn.s : CommonStrings.stateOff.s)
    }

    /// "Pro-Q 4 ×23"
    private var label: String { slot.count > 1 ? "\(slot.name) ×\(slot.count)" : slot.name }
}

/// The tick box: filled light with a check when the plugin stays enabled, a hairline outline when
/// it will be switched off.
private struct CheckMark: View {
    let isOn: Bool
    let isEnabled: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? (isEnabled ? Theme.light : Theme.textDim) : .clear)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isOn ? .clear : Theme.hairline, lineWidth: 1.4)
            if isOn {
                IconView(icon: .check, size: 9, weight: .bold).foregroundStyle(Theme.onLight)
            }
        }
        .frame(width: 16, height: 16)
        .animation(Theme.hoverAnimation, value: isOn)
    }
}
