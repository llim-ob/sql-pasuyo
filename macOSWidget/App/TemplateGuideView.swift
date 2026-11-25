import SwiftUI

private struct TemplateReference: Identifiable {
    let id: String
    let title: String
    let operation: String
    let description: String
}

struct TemplateGuideView: View {
    private let references = [
        TemplateReference(
            id: "reload.txt",
            title: "Reload",
            operation: "Reload",
            description: "Standard reload SQL and production reprocessing instructions."
        ),
        TemplateReference(
            id: "ai_reload.txt",
            title: "AI adapter reload",
            operation: "Reload (automatic template selection)",
            description: "Used for reloads when the read-only adapter lookup identifies an AI Python command."
        ),
        TemplateReference(
            id: "rename.txt",
            title: "Rename",
            operation: "Rename",
            description: "Reload SQL plus the filename update. The destination filename must be in the Teamwork task."
        ),
        TemplateReference(
            id: "delete1.txt",
            title: "Delete (new backup tables)",
            operation: "Delete, mode 1",
            description: "Creates the detail backup table, then backs up and deletes the requested rows."
        ),
        TemplateReference(
            id: "delete2.txt",
            title: "Delete (existing backup tables)",
            operation: "Delete, mode 2",
            description: "Backs up and deletes the requested rows using existing backup tables."
        ),
        TemplateReference(
            id: "ccs_delete.txt",
            title: "CCS duplicate removal",
            operation: "CCS delete (automatic classification)",
            description: "Removes duplicate image records from the CCS tables."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Supported templates")
                    .font(.title2.weight(.semibold))
                Text("The selected operation determines how the Teamwork task is processed. Replace blob uses the standard reload template with the replace-blob request label and Teamwork tag. Delete mode is selected from a read-only Oracle lookup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(references) { reference in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(reference.title).font(.headline)
                            Spacer()
                            Text(reference.operation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(reference.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(templateText(for: reference.id))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                    }
                    Divider()
                }

                Text("Template placeholders")
                    .font(.headline)
                Text("Values such as {fileids}, {feed_id}, {adapter_id}, {detail_table}, and {rename_updates} are filled from the Teamwork task and read-only lookups before the issue is created. The SQL and shell instructions are included as text in the GitHub issue; the app does not execute them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private func templateText(for filename: String) -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let templateURL = repositoryRoot.appendingPathComponent("template/\(filename)")
        return (try? String(contentsOf: templateURL, encoding: .utf8))
            ?? "Could not read template/\(filename). Keep the repository in its installed location and reopen the app."
    }
}
