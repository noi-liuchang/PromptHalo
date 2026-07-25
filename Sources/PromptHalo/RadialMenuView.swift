import SwiftUI

@MainActor
final class RadialMenuModel: ObservableObject {
    @Published var prompts: [PromptItem?] = Array(repeating: nil, count: 5)
    @Published var selectedSlot: Int?
}

private struct RingSegment: Shape {
    let startDegrees: Double
    let endDegrees: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(endDegrees),
            endAngle: .degrees(startDegrees),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

struct RadialMenuView: View {
    @ObservedObject var model: RadialMenuModel
    @ObservedObject private var language = AppLanguageSettings.shared

    private let slotAngles = [-90.0, -18.0, 54.0, 126.0, 198.0]

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let slot = index + 1
                let isSelected = model.selectedSlot == slot

                RingSegment(
                    startDegrees: slotAngles[index] - 33,
                    endDegrees: slotAngles[index] + 33,
                    innerRadius: 61,
                    outerRadius: 148
                )
                .fill(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.88))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .overlay {
                    RingSegment(
                        startDegrees: slotAngles[index] - 33,
                        endDegrees: slotAngles[index] + 33,
                        innerRadius: 61,
                        outerRadius: 148
                    )
                    .stroke(
                        isSelected
                            ? Color.white.opacity(0.82)
                            : Color.primary.opacity(0.13),
                        lineWidth: isSelected ? 1.6 : 0.8
                    )
                }
                .shadow(
                    color: .black.opacity(isSelected ? 0.22 : 0.11),
                    radius: isSelected ? 13 : 7,
                    y: 4
                )
                .animation(.snappy(duration: 0.13), value: isSelected)

                slotLabel(index: index, isSelected: isSelected)
            }

            Circle()
                .fill(.regularMaterial)
                .frame(width: 104, height: 104)
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.14), radius: 12, y: 5)

            centerContent
                .frame(width: 90)
        }
        .frame(width: 330, height: 330)
        .drawingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            language.text(
                "PromptHalo 快捷轮盘",
                "PromptHalo Quick Wheel"
            )
        )
    }

    @ViewBuilder
    private func slotLabel(index: Int, isSelected: Bool) -> some View {
        let angle = slotAngles[index] * .pi / 180
        let radius: CGFloat = 108
        let prompt = model.prompts[index]

        VStack(spacing: 4) {
            Text("\(index + 1)")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(
                prompt?.title
                    ?? language.text("空位", "Empty")
            )
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 78)
                .opacity(prompt == nil ? 0.48 : 0.94)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .position(
            x: 165 + cos(angle) * radius,
            y: 165 + sin(angle) * radius
        )
        .animation(.snappy(duration: 0.13), value: isSelected)
    }

    @ViewBuilder
    private var centerContent: some View {
        if let slot = model.selectedSlot {
            let prompt = model.prompts[slot - 1]
            VStack(spacing: 5) {
                Image(systemName: prompt == nil ? "plus" : "text.quote")
                    .font(.system(size: 19, weight: .semibold))
                Text(
                    prompt?.title
                        ?? language.text(
                            "空位 \(slot)",
                            "Empty Slot \(slot)"
                        )
                )
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 5) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(
                    language.text(
                        "移动方向\n或按 1–5",
                        "Move pointer\nor press 1–5"
                    )
                )
                    .font(.system(size: 10, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
