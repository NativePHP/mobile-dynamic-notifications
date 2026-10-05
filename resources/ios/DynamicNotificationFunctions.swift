import Foundation
import SwiftUI
import UIKit

enum DynamicNotificationFunctions {
    class Show: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            guard let id = parameters["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let title = parameters["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ["error": "A non-empty id and title are required."]
            }
            let duration: Double?
            if parameters["duration"] is NSNull {
                duration = nil
            } else {
                let milliseconds = (parameters["duration"] as? NSNumber)?.doubleValue ?? 3600
                guard milliseconds.isFinite, (250...86400000).contains(milliseconds) else {
                    return ["error": "Duration must be null or 250...86400000 milliseconds."]
                }
                duration = milliseconds / 1000
            }
            let accent = parameters["accent"] as? String ?? "#60A5FA"
            guard accent.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
                return ["error": "Accent must be a six-digit hex color."]
            }
            let item = DynamicNotificationItem(
                id: id, title: title, message: parameters["message"] as? String,
                symbol: parameters["symbol"] as? String ?? "bell.fill", accent: accent,
                duration: duration, data: parameters["data"] ?? [:]
            )
            return onMain { DynamicNotificationPresenter.shared.show(item) }
        }
    }

    class Dismiss: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            onMain {
                ["dismissed": DynamicNotificationPresenter.shared.dismiss(
                    id: parameters["id"] as? String, reason: "programmatic"
                )]
            }
        }
    }

    private static func onMain<T>(_ operation: () -> T) -> T {
        if Thread.isMainThread { return operation() }
        return DispatchQueue.main.sync(execute: operation)
    }
}

struct DynamicNotificationItem {
    let id: String
    let title: String
    let message: String?
    let symbol: String
    let accent: String
    let duration: Double?
    let data: Any

    var color: Color {
        let hex = UInt32(accent.dropFirst(), radix: 16) ?? 0x60A5FA
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }
}

final class DynamicNotificationState: ObservableObject {
    @Published var expanded = false
    @Published var dismissing = false
}

/// A separate, non-key window keeps the banner above native screens and sheets,
/// while forwarding every touch outside its card to the application underneath.
final class DynamicNotificationWindow: UIWindow {
    var cardRect = CGRect.zero
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard cardRect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

final class DynamicNotificationHost: UIHostingController<DynamicNotificationView> {
    var onResize: (() -> Void)?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        onResize?()
    }
}

final class DynamicNotificationPresenter {
    static let shared = DynamicNotificationPresenter()
    private var window: DynamicNotificationWindow?
    private var item: DynamicNotificationItem?
    private var state: DynamicNotificationState?
    private var timer: DispatchWorkItem?
    private var token = UUID()
    private var backgroundObserver: NSObjectProtocol?

    private init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let scene = notification.object as? UIWindowScene,
                  scene === self.window?.windowScene else { return }
            self.remove(reason: "background")
        }
    }

    func show(_ notification: DynamicNotificationItem) -> [String: Any] {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let appWindow = scene.windows.first(where: { $0.isKeyWindow }) else {
            return ["error": "Dynamic notifications require a foreground application window."]
        }

        remove(reason: "replaced")
        let generation = UUID()
        token = generation
        item = notification
        let state = DynamicNotificationState()
        self.state = state

        let width = appWindow.bounds.width
        let top = appWindow.safeAreaInsets.top
        // iOS exposes safe areas, not the hardware island bounds. Only use the
        // island approximation on portrait iPhones with a sufficiently tall inset.
        let island = appWindow.traitCollection.userInterfaceIdiom == .phone && top >= 51
            && appWindow.bounds.height > width
        let cardWidth = min(width - 32, 396)
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let messageHeight = notification.message?.isEmpty == false ? font.lineHeight * 2 : 0
        let height = max(78, UIFont.preferredFont(forTextStyle: .headline).lineHeight + messageHeight + 28)
        let card = CGRect(x: (width - cardWidth) / 2, y: top + 16, width: cardWidth, height: height)
        let origin = island
            ? CGRect(x: (width - 18) / 2, y: max(8, top - 27), width: 18, height: 18)
            : CGRect(x: (width - 100) / 2, y: top, width: 100, height: 8)

        let overlay = DynamicNotificationWindow(windowScene: scene)
        overlay.frame = appWindow.bounds
        overlay.backgroundColor = .clear
        overlay.windowLevel = .alert + 1
        overlay.cardRect = card
        let root = DynamicNotificationView(
            item: notification, state: state, card: card, origin: origin, island: island,
            tap: { [weak self] in self?.tap(generation) },
            dismiss: { [weak self] in
                guard self?.token == generation else { return }
                _ = self?.dismiss(reason: "swipe")
            }
        )
        let host = DynamicNotificationHost(rootView: root)
        host.view.backgroundColor = .clear
        host.onResize = { [weak self] in
            guard self?.token == generation else { return }
            self?.remove(reason: "layoutChanged")
        }
        overlay.rootViewController = host
        window = overlay
        overlay.isHidden = false // Never make this window key: preserve text input.

        DispatchQueue.main.async { [weak self] in
            guard let self, self.token == generation else { return }
            UIAccessibility.post(notification: .announcement, argument: [notification.title, notification.message].compactMap { $0 }.joined(separator: ". "))
        }
        if let duration = notification.duration {
            let task = DispatchWorkItem { [weak self] in
                guard self?.token == generation else { return }
                _ = self?.dismiss(reason: "timeout")
            }
            timer = task
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.70, execute: task)
        }
        return ["success": true, "id": notification.id]
    }

    @discardableResult
    func dismiss(id: String? = nil, reason: String) -> Bool {
        guard let item, let state, !state.dismissing, id == nil || id == item.id else { return false }
        timer?.cancel()
        timer = nil
        state.dismissing = true
        let generation = token
        withAnimation(.easeInOut(duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.28)) {
            state.expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard self?.token == generation else { return }
            self?.remove(reason: reason)
        }
        return true
    }

    private func tap(_ generation: UUID) {
        guard token == generation, let item, state?.dismissing == false else { return }
        // Mark it dismissing before emitting an event, so repeated taps fire once.
        guard dismiss(reason: "tap") else { return }
        emit("NotificationTapped", item: item)
    }

    private func remove(reason: String) {
        timer?.cancel()
        timer = nil
        let old = item
        item = nil
        state = nil
        token = UUID()
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let old { emit("NotificationDismissed", item: old, reason: reason) }
    }

    private func emit(_ event: String, item: DynamicNotificationItem, reason: String? = nil) {
        var payload: [String: Any?] = ["id": item.id, "data": item.data]
        if let reason { payload["reason"] = reason }
        LaravelBridge.shared.send?("NativePHP\\DynamicNotifications\\Events\\\(event)", payload)
    }
}

struct DynamicNotificationView: View {
    let item: DynamicNotificationItem
    @ObservedObject var state: DynamicNotificationState
    let card: CGRect
    let origin: CGRect
    let island: Bool
    let tap: () -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !reduceMotion {
                DynamicNotificationGoo(progress: state.expanded ? 1 : 0, card: card.offsetBy(dx: 0, dy: drag), origin: origin, island: island)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 13) {
                Image(systemName: UIImage(systemName: item.symbol) == nil ? "bell.fill" : item.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(item.color)
                    .frame(width: 42, height: 42)
                    .background(item.color.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    if let message = item.message, !message.isEmpty {
                        Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.74)).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(width: card.width, height: card.height)
            .background(reduceMotion ? Color.black : Color.clear, in: RoundedRectangle(cornerRadius: card.height / 2))
            .contentShape(RoundedRectangle(cornerRadius: card.height / 2))
            .opacity(state.expanded ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (state.expanded ? 1 : 0.72))
            .offset(x: card.minX, y: card.minY + drag)
            .onTapGesture(perform: tap)
            .gesture(DragGesture(minimumDistance: 10)
                .onChanged { value in drag = max(-20, min(20, value.translation.height * 0.25)) }
                .onEnded { value in
                    if abs(value.translation.height) > 24 || abs(value.predictedEndTranslation.height) > 80 { dismiss() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 }
                })
            .allowsHitTesting(state.expanded && !state.dismissing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([item.title, item.message].compactMap { $0 }.joined(separator: ". "))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, tap)
            .accessibilityAction(named: Text("Dismiss"), dismiss)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task {
            // A dispatch from show() can run before the hosting view's first
            // render, coalescing collapsed and expanded into a single frame.
            // Give each newly mounted overlay a collapsed frame of its own.
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            guard !Task.isCancelled, !state.dismissing else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.62, dampingFraction: 0.76)) {
                state.expanded = true
            }
        }
    }
}

/// A narrow drop leaves the island's center before opening into a full card.
/// The hardware island is never redrawn: only the drop and its thin neck exist.
struct DynamicNotificationGoo: View, Animatable {
    var progress: CGFloat
    let card: CGRect
    let origin: CGRect
    let island: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let p = max(0, min(1.08, progress))
            let expansion = min(1, max(0, (p - 0.42) / 0.58))
            let expand = expansion * expansion * (3 - 2 * expansion)
            let width = origin.width + (card.width - origin.width) * expand
            let height = origin.height + (card.height - origin.height) * expand
            let centerY = origin.midY + (card.midY - origin.midY) * p
            let rect = CGRect(x: card.midX - width / 2, y: centerY - height / 2, width: width, height: height)
            context.addFilter(.alphaThreshold(min: 0.45, color: .black))
            context.addFilter(.blur(radius: 4))
            context.drawLayer { layer in
                if island && p > 0 && p < 0.66 {
                    let center = origin.midX
                    let start = origin.midY
                    let end = max(start, rect.minY + 8)
                    let neckWidth = 7 * max(0, 1 - p / 0.66)
                    let middle = (start + end) / 2
                    var neck = Path()
                    neck.move(to: CGPoint(x: center - 7, y: start))
                    neck.addCurve(to: CGPoint(x: center - neckWidth, y: end),
                                  control1: CGPoint(x: center - 3, y: middle),
                                  control2: CGPoint(x: center - neckWidth, y: middle))
                    neck.addLine(to: CGPoint(x: center + neckWidth, y: end))
                    neck.addCurve(to: CGPoint(x: center + 7, y: start),
                                  control1: CGPoint(x: center + neckWidth, y: middle),
                                  control2: CGPoint(x: center + 3, y: middle))
                    neck.closeSubpath()
                    layer.fill(neck, with: .color(.black))
                }
                layer.fill(Path(roundedRect: rect, cornerRadius: height / 2), with: .color(.black))
            }
        }
        .opacity(island ? 1 : min(1, max(0, progress)))
    }
}
