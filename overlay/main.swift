import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var webView: WKWebView!
    var isVoiceActive: Bool = false
    var isAntigravityFront: Bool = false
    var isVisible: Bool = false
    var forceTest: Bool = false
    var checkTimer: Timer?
    var statePath: String = ""
    var htmlPath: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Sin icono en el Dock ni barra de menú

        if CommandLine.arguments.contains("--test") {
            forceTest = true
        }

        let home = NSHomeDirectory()
        statePath = "\(home)/.config/ultron-assistant/state.json"
        htmlPath = "\(home)/.config/ultron-assistant/overlay/index.html"

        let screen = NSScreen.main ?? (NSScreen.screens.first ?? NSScreen())
        let visibleFrame = screen.visibleFrame
        let size: CGFloat = 200
        let margin: CGFloat = 24
        let x = visibleFrame.maxX - size - margin
        let y = visibleFrame.minY + margin
        let frame = NSRect(x: x, y: y, width: size, height: size)

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true // Click-through: los clics pasan directo a la ventana inferior
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: size), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]

        panel.contentView = webView

        let fileURL = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())

        panel.alphaValue = 0.0
        panel.orderOut(nil)

        let frontApp = NSWorkspace.shared.frontmostApplication
        isAntigravityFront = (frontApp?.bundleIdentifier == "com.google.antigravity")

        // Observador nativo de cambio de aplicación (0% CPU, disparado por macOS)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let activeApp = NSWorkspace.shared.frontmostApplication
            self.isAntigravityFront = (activeApp?.bundleIdentifier == "com.google.antigravity")
            self.evaluateVisibility()
        }

        readState()

        // Temporizador de respaldo cada 0.6s para máxima reactividad
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.readState()
        }
    }

    func readState() {
        if forceTest {
            if !isVoiceActive {
                isVoiceActive = true
                evaluateVisibility()
            }
            return
        }

        guard FileManager.default.fileExists(atPath: statePath) else {
            if isVoiceActive {
                isVoiceActive = false
                evaluateVisibility()
            }
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let active = json["voice_active"] as? Bool ?? false
                if active != self.isVoiceActive {
                    self.isVoiceActive = active
                    self.evaluateVisibility()
                }
            }
        } catch { }
    }

    func evaluateVisibility() {
        // Regla: Se muestra si hay voz activa Y Antigravity NO está al frente (o en modo test)
        let shouldShow = forceTest || (isVoiceActive && !isAntigravityFront)

        if shouldShow && !isVisible {
            isVisible = true
            panel.orderFrontRegardless()
            webView.evaluateJavaScript("window.startAnimation && window.startAnimation()", completionHandler: nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 1.0
            }
        } else if !shouldShow && isVisible {
            isVisible = false
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                guard let self = self, !self.isVisible else { return }
                self.panel.orderOut(nil)
                self.webView.evaluateJavaScript("window.pauseAnimation && window.pauseAnimation()", completionHandler: nil)
            })
        }
    }
}

// Configurar captura de señales para cierre limpio
signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
