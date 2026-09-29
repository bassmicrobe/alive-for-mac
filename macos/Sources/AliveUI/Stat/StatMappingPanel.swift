// Port of the left-hand panel of nebula/NebulaForm.cs (LayoutAll / PaintPanel / PaintLegend).
import SwiftUI

struct StatMappingPanel: View {
    let model: StatModel

    private static let channels: [StatStrings] = [.channelX, .channelY, .channelZ, .channelSize, .channelFade, .channelColour]

    var body: some View {
        // Read so the panel follows the model (config and legend are observed).
        let config = model.config
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                caption(StatStrings.mapping.s)
                ForEach(0..<6, id: \.self) { i in channelRow(i, config) }

                if model.showsPalette {
                    StatDropField(label: StatStrings.palette.s,
                                  items: Palette.gradients.map { ($0.id, $0.title.s) },
                                  selection: config.gradientId) { model.setGradient(id: $0) }
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    slider(StatStrings.minFade.f(Int((config.minFade * 100).rounded())), value: config.minFade) {
                        model.setMinFade($0)
                    }
                    slider(StatStrings.maxFade.f(Int((config.maxFade * 100).rounded())), value: config.maxFade) {
                        model.setMaxFade($0)
                    }
                    slider(StatStrings.minSize.f(Self.px(config.minSize)),
                           value: Self.unit(config.minSize, NebulaConfig.minSizeRange)) {
                        model.setMinSize(Self.scaled($0, NebulaConfig.minSizeRange))
                    }
                    slider(StatStrings.maxSize.f(Self.px(config.maxSize)),
                           value: Self.unit(config.maxSize, NebulaConfig.maxSizeRange)) {
                        model.setMaxSize(Self.scaled($0, NebulaConfig.maxSizeRange))
                    }
                }
                .padding(.top, 10)

                legend(config)
                    .padding(.top, 12)
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    // MARK: rows

    private func channelRow(_ i: Int, _ config: NebulaConfig) -> some View {
        HStack(spacing: 6) {
            StatDropField(label: Self.channels[i].s,
                          items: model.metrics.all.map { ($0.id, $0.title.s) },
                          selection: config.ids[i],
                          isDimmed: !config.isOn[i]) { model.setMetric(i, id: $0) }
            StatChannelSwitch(isOn: config.isOn[i], help: StatStrings.channelSwitchHelp.s) { model.setChannel(i, isOn: $0) }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.fBadge)
            .kerning(0.6)
            .foregroundStyle(Theme.secondaryText)
            .textCase(Localizer.shared.lang == .en ? .uppercase : nil)
            .padding(.leading, 4)
    }

    private func slider(_ title: String, value: Double, _ onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            caption(title)
            StatSlider(value: value, onChange: onChange, label: title)
        }
        .padding(.bottom, 6)
    }

    // MARK: legend

    @ViewBuilder private func legend(_ config: NebulaConfig) -> some View {
        let title = model.legend == .off
            ? StatStrings.off.s : model.metrics.byId(config.ids[5]).title.s
        VStack(alignment: .leading, spacing: 8) {
            caption(StatStrings.colourLegend.f(title))
            switch model.legend {
            case .off:
                EmptyView()
            case .ramp(let gradient, let lo, let hi):
                rampBar(gradient)
                HStack {
                    Text(lo); Spacer(minLength: 8); Text(hi)
                }
                .font(Theme.fBadge)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)
            case .classes(let chips):
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          spacing: 4) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        HStack(spacing: 6) {
                            Circle().fill(Color(rgb: chip.rgb)).frame(width: 8, height: 8)
                            Text(chip.name).font(Theme.fBadge).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// The strip is 32 samples of the same `Palette.sample` the dots themselves are coloured with
    /// (the same path through LAB): the legend never disagrees with what is visible in the cloud.
    private func rampBar(_ gradient: StatGradient) -> some View {
        let steps = 32
        let stops = (0..<steps).map { i in
            let t = Double(i) / Double(steps - 1)
            return Gradient.Stop(color: Color(rgb: Palette.sample(gradient, t)), location: t)
        }
        return Capsule()
            .fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
            .frame(height: 10)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    // MARK: slider mapping

    /// The px ranges the Size sliders map 0…1 into.
    static func unit(_ v: Double, _ range: ClosedRange<Double>) -> Double {
        (v - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    static func scaled(_ unit: Double, _ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    static func px(_ v: Double) -> String { NebulaConfig.number(v, decimals: 1) }
}

extension Color {
    init(rgb: RGB8) {
        self.init(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
