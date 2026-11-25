import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingCredentials = false
    @State private var showIssueBody = false
    @State private var copiedResult: TaskResult.ID?
    @State private var retryRequest: PreparedRequest?

    private let accent = Color(red: 0.03, green: 0.43, blue: 0.39)
    private var highlight: Color {
        colorScheme == .dark ? Color(red: 0.48, green: 0.95, blue: 0.77) : accent
    }
    private let panel = Color(nsColor: .controlBackgroundColor)
    private let inset = Color(nsColor: .underPageBackgroundColor)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            composer
            if model.results.isEmpty {
                emptyWorkspace
            } else {
                HStack(spacing: 0) {
                    taskList
                    Divider()
                    if let result = model.results.first(where: { $0.id == model.selectedResult }) {
                        detail(result)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Select a task", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(panel)
                .clipShape(.rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6)) }
            }
        }
        .padding(22)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            Button("Template documentation", systemImage: "book") {
                openWindow(id: "template-guide")
            }
            Button("Credentials", systemImage: "key") {
                editingCredentials = true
            }
        }
        .sheet(isPresented: $editingCredentials) {
            credentials
        }
        .alert("Retry issue creation?", isPresented: Binding(
            get: { retryRequest != nil },
            set: { if !$0 { retryRequest = nil } }
        ), presenting: retryRequest) { request in
            Button("Retry") { model.publish(request) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Check GitHub for an existing issue for this task before retrying.")
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(highlight)
                    .frame(width: 42, height: 42)
                    .background(highlight.opacity(0.12), in: .rect(cornerRadius: 11))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SQL requests").font(.title2.weight(.semibold))
                    Text("Paste one or more Teamwork links, separated by spaces or new lines.")
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.taskLinks)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .accessibilityLabel("Teamwork task links")
                    .accessibilityHint("Paste one or more links separated by spaces or new lines.")
                if model.taskLinks.isEmpty {
                    Text("Paste Teamwork task links here")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .padding(.top, 9)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 68)
            .background(inset, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.55)).allowsHitTesting(false) }

            HStack(spacing: 12) {
                Picker("Operation", selection: $model.selectedOperation) {
                    Text("Automatic").tag("auto")
                    Text("Reload").tag("reload")
                    Text("Replace blob").tag("replace-blob")
                    Text("Rename").tag("rename")
                    Text("Delete").tag("delete")
                    Text("Reload and delete").tag("reload-delete")
                }
                .fixedSize()

                Spacer()
                if !model.hasTeamworkCredential {
                    Button("Set up Teamwork", systemImage: "key") { editingCredentials = true }
                        .buttonStyle(.link)
                }
                if model.isGenerating {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.generate()
                } label: {
                    Label(model.isGenerating ? "Generating…" : "Generate previews",
                          systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!model.canGenerate)
            }
        }
        .padding(16)
        .background(panel, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6)).allowsHitTesting(false) }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(highlight)
                .frame(width: 64, height: 64)
                .background(highlight.opacity(0.10), in: .rect(cornerRadius: 17))
                .accessibilityHidden(true)
            Text("No previews yet").font(.headline)
            Text("Generated SQL will appear here for review.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tasks").font(.headline)
                Spacer()
                Text(model.results.count.formatted())
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            Divider()
            List(model.results, selection: $model.selectedResult) { result in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: resultSymbol(result))
                        .foregroundStyle(result.error == nil ? Color.secondary : Color.orange)
                        .frame(width: 15)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.request?.title ?? result.link)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                        Text(resultSubtitle(result))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .tag(result.id)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 235)
        .background(inset.opacity(0.6))
    }

    private func resultSymbol(_ result: TaskResult) -> String {
        if result.error != nil { return "exclamationmark.circle" }
        guard let request = result.request else { return "clock" }
        return model.published[request.taskId] == nil ? "doc.text" : "checkmark.circle"
    }

    private func resultSubtitle(_ result: TaskResult) -> String {
        if result.error != nil { return "Preview unavailable" }
        guard let request = result.request else { return "Queued or generating" }
        if model.published[request.taskId] != nil { return "Issue created" }
        return "#\(request.taskId) · \(operationLabel(request.operation))"
    }

    @ViewBuilder
    private func detail(_ result: TaskResult) -> some View {
        if let request = result.request {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(request.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                        .textSelection(.enabled)
                    HStack(spacing: 10) {
                        if let taskURL = URL(string: result.link) {
                            Link(destination: taskURL) {
                                Label("Teamwork #\(request.taskId)", systemImage: "arrow.up.right")
                            }
                        }
                        Text(operationLabel(request.operation))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))
                }

                VStack(spacing: 0) {
                    HStack {
                        Picker("Preview", selection: $showIssueBody) {
                            Text("Request text").tag(false)
                            Text("GitHub issue body").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Spacer(minLength: 4)
                        Button(copiedResult == result.id ? "Copied" : "Copy request",
                               systemImage: copiedResult == result.id ? "checkmark" : "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setString(request.requestText, forType: .string) {
                                copiedResult = result.id
                            }
                        }
                        .buttonStyle(.borderless)
                        .fixedSize()
                    }
                    .padding(10)
                    Divider()
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: showIssueBody ? request.issueBody : request.requestText)
                            .font(.system(.callout, design: .monospaced))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(inset)
                    .id(showIssueBody)
                }
                .clipShape(.rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.separator.opacity(0.6)).allowsHitTesting(false) }
                .id(result.id)

                publishingFooter(request)
            }
            .padding(16)
        } else if let error = result.error {
            ContentUnavailableView {
                Label("Preview unavailable", systemImage: "exclamationmark.circle")
            } description: {
                VStack(spacing: 8) {
                    Text(result.link)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(error)
                }
                .textSelection(.enabled)
                .padding(.horizontal, 18)
            }
        } else {
            ProgressView("Waiting for preview…")
        }
    }

    private func publishingFooter(_ request: PreparedRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !model.hasGitHubToken && model.published[request.taskId] == nil {
                    Button("Set up GitHub", systemImage: "key") { editingCredentials = true }
                        .buttonStyle(.link)
                }
                Spacer()
                if let published = model.published[request.taskId] {
                    Link(destination: published.issueUrl) {
                        Label("Open created issue", systemImage: "arrow.up.right.square")
                    }
                } else {
                    Button(model.publishingTask == request.taskId ? "Publishing…" : "Create GitHub issue",
                           systemImage: "arrow.up.right.square") {
                        if model.publishErrors[request.taskId] != nil {
                            retryRequest = request
                        } else {
                            model.publish(request)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.hasGitHubToken || !model.hasTeamworkCredential
                        || model.isGenerating || model.publishingTask != nil)
                }
            }
            if let taggingError = model.published[request.taskId]?.tagError {
                Text("Issue created. Teamwork tagging failed: \(taggingError)")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else if let error = model.publishErrors[request.taskId] {
                Text("Could not confirm issue creation. Check GitHub before retrying. \(error)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var credentials: some View {
        Form {
            Picker("Teamwork authentication", selection: $model.teamworkUsesAPIKey) {
                Text("API key").tag(true)
                Text("OAuth token").tag(false)
            }
            SecureField(model.teamworkUsesAPIKey ? "Teamwork API key" : "Teamwork OAuth token",
                        text: $model.teamworkToken)
            SecureField("GitHub token (for publishing)", text: $model.githubToken)
            if !model.credentialStatus.isEmpty {
                Text(model.credentialStatus).foregroundStyle(.secondary)
            }
            HStack {
                Button("Save credentials") { model.saveCredentials() }
                Spacer()
                Button("Done") { editingCredentials = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func operationLabel(_ operation: String) -> String {
        switch operation {
        case "replace-blob": "Replace blob"
        case "reload-delete": "Reload and delete"
        case "ccs-delete": "CCS delete"
        default: operation.capitalized
        }
    }
}
