// Port of src/Toast.cs: a short message in the corner, held for a couple of seconds, faded out.
// It asks nothing and waits for no answer; the mouse passes through it.
import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    enum Kind { case info, error }

    let id = UUID()
    let text: String
    let kind: Kind
}

struct ToastOverlay: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(app.toasts) { toast in
                ToastView(message: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(Theme.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: app.toasts)
        .allowsHitTesting(false)
    }
}

private struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(message.kind == .error ? Theme.red : Theme.green)
                .frame(width: 7, height: 7)
            Text(message.text)
                .font(Theme.fBody)
                .foregroundStyle(Theme.text)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.surfacePressed, in: RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardR, style: .continuous)
                .strokeBorder(Theme.cardHighlight, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .frame(maxWidth: 420, alignment: .trailing)
    }
}
