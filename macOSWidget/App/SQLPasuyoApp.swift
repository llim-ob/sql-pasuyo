import SwiftUI

@main
struct SQLPasuyoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("SQL Pasuyo", systemImage: "arrow.triangle.2.circlepath") {
            ContentView(model: model)
                .frame(width: 360)
                .onOpenURL { url in
                    if url.scheme == "sqlpasuyo", url.host == "submit",
                       let task = url.queryParameters["url"] {
                        model.taskURL = task
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Template documentation", id: "template-guide") {
            TemplateGuideView()
        }
        .defaultSize(width: 760, height: 720)
    }
}

extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?
            .reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
    }
}
