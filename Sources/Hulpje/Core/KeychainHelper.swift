import Foundation

enum KeychainHelper {
    private static var cachedKey: String?

    static func getOpenAIKey() -> String? {
        if let key = cachedKey { return key }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", "claude-mcp",
            "-s", "OPENAI_API_KEY",
            "-w"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else {
                return nil
            }
            cachedKey = key
            return key
        } catch {
            return nil
        }
    }
}
