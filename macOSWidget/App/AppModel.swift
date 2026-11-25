import Foundation
import Security

struct PreparedRequest: Codable, Sendable {
    let taskId: String
    let title: String
    let operation: String
    let requestDetails: String
    let requestText: String
    let issueBody: String
}

struct PublishedRequest: Decodable, Sendable {
    let issueUrl: URL
    let tagError: String?
}

struct TaskResult: Identifiable {
    let id = UUID()
    let link: String
    var request: PreparedRequest?
    var error: String?
}

@MainActor @Observable
final class AppModel {
    var taskLinks = ""
    var selectedOperation = "auto"
    var githubToken = Keychain.read("github") ?? ""
    var teamworkToken = Keychain.read("teamwork") ?? ""
    var teamworkUsesAPIKey = UserDefaults.standard.object(forKey: "teamworkAPIKey") as? Bool ?? true
    var results: [TaskResult] = []
    var selectedResult: TaskResult.ID?
    var isGenerating = false
    var publishingTask: String?
    var published: [String: PublishedRequest] = [:]
    var publishErrors: [String: String] = [:]
    var credentialStatus = ""

    var canGenerate: Bool {
        !taskLinks.split(whereSeparator: \.isWhitespace).isEmpty
            && hasTeamworkCredential && !isGenerating && publishingTask == nil
    }

    var hasTeamworkCredential: Bool { !teamworkToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasGitHubToken: Bool { !githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func saveCredentials() {
        let teamworkSaved = Keychain.save(teamworkToken, key: "teamwork")
        let githubSaved = Keychain.save(githubToken, key: "github")
        if teamworkSaved {
            UserDefaults.standard.set(teamworkUsesAPIKey, forKey: "teamworkAPIKey")
        }
        credentialStatus = teamworkSaved && githubSaved
            ? "Credentials saved to Keychain."
            : "Could not save all credentials to Keychain."
    }

    func generate() {
        guard canGenerate else { return }
        var seen = Set<String>()
        let inputs = taskLinks.split(whereSeparator: \.isWhitespace).compactMap { token -> TaskResult? in
            let link = String(token)
            guard let taskID = Self.taskID(from: link) else {
                return TaskResult(link: link, error: "Enter an HTTPS Objectbright Teamwork task link.")
            }
            return seen.insert(taskID).inserted ? TaskResult(link: link) : nil
        }
        results = inputs
        selectedResult = inputs.first(where: { $0.error == nil })?.id ?? inputs.first?.id
        isGenerating = true
        let workflow = workflow()
        let operation = selectedOperation
        Task {
            defer { isGenerating = false }
            for (index, input) in inputs.enumerated() where input.error == nil {
                var arguments = ["--preview-json", input.link]
                if operation != "auto" {
                    arguments += ["--operation", operation]
                }
                do {
                    results[index].request = try await workflow.run(arguments, as: PreparedRequest.self)
                } catch {
                    results[index].error = error.localizedDescription
                }
            }
        }
    }

    func publish(_ request: PreparedRequest) {
        guard hasGitHubToken, hasTeamworkCredential, !isGenerating, publishingTask == nil,
              published[request.taskId] == nil else { return }
        publishingTask = request.taskId
        publishErrors[request.taskId] = nil
        let workflow = workflow()
        Task {
            defer { publishingTask = nil }
            do {
                let input = try Workflow.encoder().encode(request)
                published[request.taskId] = try await workflow.run(
                    ["--publish-json"], input: input, as: PublishedRequest.self
                )
            } catch {
                publishErrors[request.taskId] = error.localizedDescription
            }
        }
    }

    private func workflow() -> Workflow {
        Workflow(
            githubToken: githubToken.trimmingCharacters(in: .whitespacesAndNewlines),
            teamworkToken: teamworkToken.trimmingCharacters(in: .whitespacesAndNewlines),
            teamworkUsesAPIKey: teamworkUsesAPIKey
        )
    }

    private static func taskID(from link: String) -> String? {
        guard let url = URLComponents(string: link), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "objectbright.teamwork.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let parts = url.percentEncodedPath.components(separatedBy: "/")
        return zip(parts, parts.dropFirst()).first { name, id in
            name == "tasks" && id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
        }.flatMap {
            let id = String($0.1.drop(while: { $0 == "0" }))
            return id.isEmpty ? nil : id
        }
    }
}

private struct Workflow: Sendable {
    let githubToken: String
    let teamworkToken: String
    let teamworkUsesAPIKey: Bool

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    func run<Output: Decodable & Sendable>(
        _ arguments: [String], input: Data? = nil, as type: Output.Type
    ) async throws -> Output {
        try await Task.detached {
            let data = try execute(arguments, input: input)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let result = try? decoder.decode(type, from: data) else {
                throw WorkflowError(message: "The workflow returned an unreadable response.")
            }
            return result
        }.value
    }

    private func execute(_ arguments: [String], input: Data?) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let python = root.appendingPathComponent(".venv/bin/python")
        let script = root.appendingPathComponent("auto.py")
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: script.path) else {
            throw WorkflowError(message: "Could not find the checkout or virtual environment. Run the installer again.")
        }

        let process = Process()
        process.executableURL = python
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["GITHUB_TOKEN"] = githubToken
        environment["TW_API_KEY"] = teamworkUsesAPIKey ? teamworkToken : ""
        environment["TW_ACCESS_TOKEN"] = teamworkUsesAPIKey ? "" : teamworkToken
        process.environment = environment

        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let stderrURL = scratch.appendingPathComponent("stderr")
        try Data().write(to: stderrURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stderr.close() }
        let stdin: FileHandle
        if let input {
            let stdinURL = scratch.appendingPathComponent("stdin")
            try input.write(to: stdinURL)
            stdin = try FileHandle(forReadingFrom: stdinURL)
        } else {
            stdin = .nullDevice
        }
        defer { if input != nil { try? stdin.close() } }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = stderr
        process.standardInput = stdin
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = (try? String(contentsOf: stderrURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw WorkflowError(message: error.isEmpty ? "Workflow exited with status \(process.terminationStatus)." : error)
        }
        return data
    }
}

private struct WorkflowError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Keychain {
    static func read(_ key: String) -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.objectbright.sqlpasuyo", kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        query.removeAll()
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, key: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.objectbright.sqlpasuyo", kSecAttrAccount as String: key]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
