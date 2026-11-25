import Foundation
import Security

@MainActor @Observable
final class AppModel {
    var taskURL = ""
    var selectedOperation = "auto"
    var githubToken = Keychain.read("github") ?? ""
    var teamworkToken = Keychain.read("teamwork") ?? ""
    var credentialsSaved = !(Keychain.read("github") ?? "").isEmpty
        && !(Keychain.read("teamwork") ?? "").isEmpty
    var teamworkUsesAPIKey = UserDefaults.standard.object(forKey: "teamworkAPIKey") as? Bool ?? true
    var status = "Add your credentials, then paste a Teamwork task link."
    var isRunning = false

    var configured: Bool { !githubToken.isEmpty && !teamworkToken.isEmpty }

    func saveCredentials() {
        guard configured else {
            status = "Enter both required credentials."
            return
        }
        Keychain.save(githubToken, key: "github")
        Keychain.save(teamworkToken, key: "teamwork")
        UserDefaults.standard.set(teamworkUsesAPIKey, forKey: "teamworkAPIKey")
        credentialsSaved = true
        status = "Credentials saved securely on this Mac."
    }

    func submit() {
        saveCredentials()
        guard configured else { status = "Enter both required credentials."; return }
        guard let url = URL(string: taskURL), url.scheme == "https",
              url.host?.contains("teamwork.com") == true else {
            status = "Enter a valid HTTPS Teamwork task URL."; return
        }
        isRunning = true
        status = "Processing task…"
        let operation = selectedOperation
        Task.detached { [taskURL, githubToken, teamworkToken, teamworkUsesAPIKey, operation] in
            let result = Self.run(taskURL: taskURL, githubToken: githubToken,
                                 teamworkToken: teamworkToken, usesAPIKey: teamworkUsesAPIKey,
                                 operation: operation)
            await MainActor.run { self.status = result; self.isRunning = false }
        }
    }

    nonisolated private static func run(taskURL: String, githubToken: String,
                                        teamworkToken: String, usesAPIKey: Bool,
                                        operation: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let python = root.appendingPathComponent(".venv/bin/python").path
        let script = root.appendingPathComponent("auto.py").path
        guard FileManager.default.isExecutableFile(atPath: python),
              FileManager.default.fileExists(atPath: script) else {
            return "Could not find the repository virtual environment. See README for setup."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = operation == "auto"
            ? [script, taskURL]
            : [script, taskURL, "--operation", operation]
        var environment = ProcessInfo.processInfo.environment
        environment["GITHUB_TOKEN"] = githubToken
        environment[usesAPIKey ? "TW_API_KEY" : "TW_ACCESS_TOKEN"] = teamworkToken
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0 {
                return text.components(separatedBy: .newlines)
                    .first(where: { $0.contains("Issue created:") })
                    ?? "The command finished, but no GitHub issue link was returned."
            }
            return "Failed (exit \(process.terminationStatus)): \(text)"
        } catch { return "Could not start workflow: \(error.localizedDescription)" }
    }
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
    static func save(_ value: String, key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.objectbright.sqlpasuyo", kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
