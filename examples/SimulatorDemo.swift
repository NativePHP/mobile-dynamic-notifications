// Standalone simulator harness. This substitutes ONLY the PHP bridge and hosts
// the exact plugin Swift source. It does not prove Laravel event delivery.
import SwiftUI
import UIKit

protocol BridgeFunction { func execute(parameters: [String: Any]) throws -> [String: Any] }
final class LaravelBridge {
    static let shared = LaravelBridge()
    var events: [[String: String]] = []
    var send: ((_ event: String, _ payload: [String: Any?]) -> Void)? = { event, payload in
        let row = ["event": event, "id": payload["id"] as? String ?? "", "reason": payload["reason"] as? String ?? ""]
        LaravelBridge.shared.events.append(row)
        print("PLUGIN EVENT", row)
        Smoke.save()
    }
}

enum Smoke {
    static var checks: [String: Bool] = [:]
    static func save() {
        let result: [String: Any] = ["checks": checks, "events": LaravelBridge.shared.events]
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("native-smoke.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: path)
    }
    @discardableResult static func show(_ id: String, duration: Any = NSNull()) -> [String: Any] {
        (try? DynamicNotificationFunctions.Show().execute(parameters: [
            "id": id, "title": "You're all caught up", "message": "Everything is synced and ready to go.",
            "symbol": "checkmark", "accent": "#82D9AE", "duration": duration,
            "data": ["source": "simulator"]
        ])) ?? [:]
    }
    static func later(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
    static func start() {
        later(1) {
            checks["show accepted"] = show("old", duration: 250)["success"] as? Bool == true
            checks["invalid duration rejected"] = (try? DynamicNotificationFunctions.Show().execute(parameters: ["id": "bad", "title": "Bad", "duration": -1])["error"]) != nil
        }
        later(1.15) { show("current") }
        later(2.2) {
            checks["replacement emitted"] = LaravelBridge.shared.events.contains { $0["id"] == "old" && $0["reason"] == "replaced" }
            checks["stale timer did not dismiss replacement"] = !LaravelBridge.shared.events.contains { $0["id"] == "current" }
            checks["stale targeted dismissal ignored"] = !DynamicNotificationPresenter.shared.dismiss(id: "old", reason: "programmatic")
            checks["current targeted dismissal accepted"] = DynamicNotificationPresenter.shared.dismiss(id: "current", reason: "programmatic")
        }
        later(2.6) {
            checks["programmatic event emitted once"] = LaravelBridge.shared.events.filter { $0["id"] == "current" && $0["reason"] == "programmatic" }.count == 1
            show("timeout", duration: 250)
        }
        later(4) {
            checks["timeout event emitted once"] = LaravelBridge.shared.events.filter { $0["id"] == "timeout" && $0["reason"] == "timeout" }.count == 1
            save()
            show("demo")
        }
    }
}

@main
struct DynamicNotificationDemo: App {
    var body: some Scene {
        WindowGroup {
            DemoScreen().onAppear { Smoke.start() }
        }
    }
}
struct DemoScreen: View {
    @State private var count = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer().frame(height: 116)
            Text("NATIVEPHP / iOS").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            Text("A little more\nfluid.").font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Dynamic notifications").font(.title3.weight(.semibold))
            Text("A native notification that flows from the top of your iPhone. Tap it, swipe it, or let it disappear.").foregroundStyle(.secondary)
            Button("Show notification") { Smoke.show("demo") }.buttonStyle(.borderedProminent).tint(.black)
            Button("Test touch-through: \(count)") { count += 1 }.tint(.black)
            Button("Dismiss notification") { _ = DynamicNotificationPresenter.shared.dismiss(reason: "programmatic") }.tint(.black)
            Spacer()
            Text("SwiftUI animation · PHP API").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.96, blue: 0.93))
        .preferredColorScheme(.light)
    }
}
