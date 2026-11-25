import Carbon
import SwiftUI

@main
struct SQLPasuyoApp: App {
    @NSApplicationDelegateAdaptor(ShortcutDelegate.self) private var shortcutDelegate
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SQL Pasuyo", id: "workspace") {
            ContentView(model: model)
                .frame(minWidth: 755, minHeight: 540)
                .handlesExternalEvents(preferring: ["submit"], allowing: ["submit"])
                .onOpenURL(perform: openSubmission)
        }
        .defaultSize(width: 940, height: 690)
        .handlesExternalEvents(matching: ["submit"])

        MenuBarExtra("SQL Pasuyo", systemImage: "doc.text") {
            Button("Open SQL Pasuyo") { showWorkspace() }
                .keyboardShortcut("o")
            Button("Template documentation") {
                openWindow(id: "template-guide")
                NSApp.activate()
            }
            Divider()
            Button("Quit SQL Pasuyo") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Window("Template documentation", id: "template-guide") {
            TemplateGuideView()
        }
        .defaultSize(width: 760, height: 720)
        .handlesExternalEvents(matching: [])
    }

    private func showWorkspace() {
        openWindow(id: "workspace")
        NSApp.activate()
    }

    private func openSubmission(_ url: URL) {
        guard url.scheme == "sqlpasuyo", url.host == "submit" else { return }
        if let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "url" })?.value {
            model.taskLinks = link
        }
        showWorkspace()
    }
}

final class ShortcutDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shortcut = EventHotKeyID(signature: 0x53504153, id: 1)
        let target = GetApplicationEventTarget()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(target, { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            guard status == noErr, pressed.signature == 0x53504153, pressed.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                if let url = URL(string: "sqlpasuyo://submit") {
                    NSWorkspace.shared.open(url)
                }
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        guard handlerStatus == noErr else {
            NSLog("SQL Pasuyo shortcut handler setup failed (%d).", handlerStatus)
            return
        }

        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_P), UInt32(optionKey | cmdKey), shortcut, target, 0, &hotKey
        )
        if registrationStatus != noErr {
            NSLog("SQL Pasuyo could not register Option–Command–P (%d).", registrationStatus)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
