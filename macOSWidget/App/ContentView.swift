import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var editingCredentials = false

    private var createdIssueURL: URL? {
        guard let successLine = model.status.components(separatedBy: .newlines)
                .first(where: { $0.contains("Issue created:") }),
              let marker = successLine.range(of: "Issue created:"),
              let rawURL = successLine[marker.upperBound...]
                .split(whereSeparator: \.isWhitespace).first,
              let url = URL(string: String(rawURL).trimmingCharacters(in: CharacterSet(charactersIn: ".,);"))),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "github.com",
              components.path.range(of: #"/[^/]+/[^/]+/issues/\d+"#, options: .regularExpression) != nil else {
            return nil
        }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SQL Pasuyo", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                if model.credentialsSaved {
                    Button(editingCredentials ? "Done" : "Edit") {
                        editingCredentials.toggle()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            if !model.credentialsSaved || editingCredentials {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("GitHub token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Enter GitHub token", text: $model.githubToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Teamwork credential")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Teamwork credential", selection: $model.teamworkUsesAPIKey) {
                            Text("API key").tag(true)
                            Text("OAuth token").tag(false)
                        }
                        .pickerStyle(.segmented)
                        SecureField(model.teamworkUsesAPIKey ? "Enter API key" : "Enter OAuth token",
                                    text: $model.teamworkToken)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Spacer()
                        Button("Save credentials") {
                            model.saveCredentials()
                            if model.credentialsSaved { editingCredentials = false }
                        }
                        .controlSize(.small)
                        .disabled(!model.configured)
                    }
                }
            }

            if !model.credentialsSaved || editingCredentials {
                Divider()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Teamwork task URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Paste task link", text: $model.taskURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Operation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Operation", selection: $model.selectedOperation) {
                    Text("Automatic").tag("auto")
                    Text("Reload").tag("reload")
                    Text("Replace blob").tag("replace-blob")
                    Text("Rename").tag("rename")
                    Text("Delete").tag("delete")
                    Text("Reload and delete").tag("reload-delete")
                }
                .pickerStyle(.menu)
                .disabled(model.isRunning)
            }

            Button(model.isRunning ? "Processing…" : "Create GitHub issue") {
                model.submit()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(model.isRunning || model.taskURL.isEmpty)

            if let issueURL = createdIssueURL {
                Label("Issue created successfully", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Link(destination: issueURL) {
                    Label(issueURL.absoluteString, systemImage: "arrow.up.right.square")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(issueURL.absoluteString)
            } else {
                Text(model.status)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Template documentation") {
                    openWindow(id: "template-guide")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
    }
}
