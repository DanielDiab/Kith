#if DEBUG
    import AgentCore
    import Foundation
    import SwiftUI

    #if os(macOS)
        import AppKit
    #endif

    /// Screenshot tooling for the README and the portfolio. Debug builds only.
    ///
    /// Launch with `KITH_CAPTURE_SCENES=<scenes.json>` (and on macOS `KITH_CAPTURE_DIR=<dir>`),
    /// as environment variables or launch arguments:
    ///
    ///     open Kith.app --args -KITH_CAPTURE_SCENES scenes.json -KITH_CAPTURE_DIR out -ApplePersistenceIgnoreState YES
    ///
    /// For each scene the app clears the conversation, applies the scene's settings on the demo
    /// week, asks its questions with the real models, opens the details if asked, and on macOS
    /// writes `<name>.png` of its own window (no screen-recording permission needed). On iOS it
    /// runs the first scene and stays there, for `xcrun simctl io booted screenshot`.
    ///
    ///     [{ "name": "today", "prompts": ["¿Qué tengo hoy?"], "privacy": "ownHardware",
    ///        "poisoned": false, "details": true, "dark": false, "width": 1180, "height": 900 }]
    struct CaptureScene: Decodable {
        var name: String
        var prompts: [String]?
        var privacy: String?
        var poisoned: Bool?
        var details: Bool?
        var dark: Bool?
        var width: Double?
        var height: Double?
    }

    @MainActor
    enum DemoCapture {
        private static func log(_ text: String) {
            FileHandle.standardError.write(Data("[capture] \(text)\n".utf8))
        }

        static func runIfRequested(model: AppModel) async {
            // From the environment, or from launch arguments (`-KITH_CAPTURE_SCENES <path>`),
            // which reach the app when it is started with `open --args`.
            let env = ProcessInfo.processInfo.environment
            let defaults = UserDefaults.standard
            guard let path = env["KITH_CAPTURE_SCENES"] ?? defaults.string(forKey: "KITH_CAPTURE_SCENES"),
                  let data = FileManager.default.contents(atPath: path),
                  let scenes = try? JSONDecoder().decode([CaptureScene].self, from: data)
            else {
                if env["KITH_CAPTURE_SCENES"] != nil || defaults.string(forKey: "KITH_CAPTURE_SCENES") != nil { log("couldn't read the scenes file") }
                return
            }
            let dir = (env["KITH_CAPTURE_DIR"] ?? defaults.string(forKey: "KITH_CAPTURE_DIR")).map { URL(fileURLWithPath: $0) }
            log("\(scenes.count) scenes")
            try? await Task.sleep(for: .seconds(1.5))

            #if os(macOS)
                for scene in scenes {
                    log("scene \(scene.name)")
                    await play(scene, model: model)
                    log("window: \(mainWindow.map { "\($0.frame)" } ?? "none")")
                    if let dir { snapshot(to: dir.appendingPathComponent("\(scene.name).png")) }
                }
                NSApp.terminate(nil)
            #else
                if let first = scenes.first { await play(first, model: model) }
            #endif
        }

        private static func play(_ scene: CaptureScene, model: AppModel) async {
            for write in model.pending { try? await KithRuntime.shared.reject(write.id) }
            await model.refresh()
            model.newConversation()
            var s = model.settings
            s.dataSource = .demo
            s.plantPoisonedInvite = scene.poisoned ?? false
            if let p = scene.privacy, let mode = PrivacyMode(rawValue: p) { s.privacy = mode }
            await model.apply(s)
            model.expandTraces = scene.details ?? false
            #if os(macOS)
                NSApp.appearance = NSAppearance(named: (scene.dark ?? false) ? .darkAqua : .aqua)
                if let window = mainWindow, let w = scene.width, let h = scene.height {
                    var frame = window.frame
                    frame.origin.y += frame.height - h
                    frame.size = CGSize(width: w, height: h)
                    window.setFrame(frame, display: true)
                }
            #endif
            for prompt in scene.prompts ?? [] {
                log("ask \(prompt)")
                await model.send(prompt)
                log("answered: \(model.items.last?.text.prefix(80) ?? "")")
            }
            try? await Task.sleep(for: .seconds(1.6))
        }

        #if os(macOS)
            private static var mainWindow: NSWindow? {
                NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
            }

            /// Draws the window's frame view (title bar included) into a bitmap at screen scale.
            private static func snapshot(to url: URL) {
                // focused, so the title bar shows its colours
                NSApp.activate()
                mainWindow?.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let window = mainWindow, let view = window.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        #endif
    }
#endif
