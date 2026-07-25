import AppKit
import SwiftUI

@MainActor
final class RadialMenuPanelController {
    let model = RadialMenuModel()

    private let panel: NSPanel
    private var cursorTimer: Timer?
    private let panelSize = NSSize(width: 350, height: 350)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.animationBehavior = .utilityWindow

        let hostingView = NSHostingView(rootView: RadialMenuView(model: model))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView
    }

    var selectedSlot: Int? {
        model.selectedSlot
    }

    func show(prompts: [PromptItem?]) {
        model.prompts = prompts
        model.selectedSlot = nil

        let cursor = NSEvent.mouseLocation
        let origin = NSPoint(
            x: cursor.x - panelSize.width / 2,
            y: cursor.y - panelSize.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        startCursorTracking()
    }

    func select(slot: Int?) {
        cursorTimer?.invalidate()
        cursorTimer = nil
        model.selectedSlot = slot
    }

    func hide() {
        cursorTimer?.invalidate()
        cursorTimer = nil

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.09
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak panel] in
                panel?.orderOut(nil)
            }
        )
    }

    private func startCursorTracking() {
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 45.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSelectionFromCursor()
            }
        }
        if let cursorTimer {
            RunLoop.main.add(cursorTimer, forMode: .common)
        }
    }

    private func updateSelectionFromCursor() {
        let point = NSEvent.mouseLocation
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)

        guard distance >= 57 else {
            if model.selectedSlot != nil {
                model.selectedSlot = nil
            }
            return
        }

        let angle = atan2(dy, dx) * 180 / .pi
        let centers = [90.0, 18.0, -54.0, -126.0, 162.0]

        let nearest = centers.enumerated().min { lhs, rhs in
            angularDistance(angle, lhs.element) < angularDistance(angle, rhs.element)
        }?.offset

        if let nearest, model.selectedSlot != nearest + 1 {
            model.selectedSlot = nearest + 1
        }
    }

    private func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }
}
