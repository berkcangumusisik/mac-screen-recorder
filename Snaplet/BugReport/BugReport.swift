import Foundation

/// A bug report the user is writing. Everything here is typed or ticked by the
/// user: Snaplet never fills in the device name, the account name or file paths.
struct BugReport: Equatable {
    var title = ""
    var steps = ""
    var expected = ""
    var actual = ""

    var includeSystemVersion = true
    var includeAppVersion = true
    var includeHardwareModel = false
    var extraEnvironment = ""

    /// File names to mention in the report, without any path.
    var attachmentNames: [String] = []

    static var systemVersionLine: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var appVersionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Snaplet \(short) (\(build))"
    }

    /// Hardware family, e.g. "Apple silicon (arm64)". Deliberately coarse — no
    /// serial number, no host name.
    static var hardwareLine: String {
        #if arch(arm64)
        return "Apple silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }

    /// Exactly what will be written, so the user can read it before sharing.
    var environmentPreview: String {
        var lines: [String] = []
        if includeSystemVersion { lines.append(Self.systemVersionLine) }
        if includeAppVersion { lines.append(Self.appVersionLine) }
        if includeHardwareModel { lines.append(Self.hardwareLine) }
        let extra = extraEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append(extra) }
        return lines.joined(separator: "\n")
    }

    var markdown: String {
        var output = "# \(title.isEmpty ? "Bug report" : title)\n\n"

        output += "## Steps to reproduce\n\n"
        output += section(steps, placeholder: "1. \n2. \n3. ")
        output += "\n\n## Expected behavior\n\n"
        output += section(expected, placeholder: "_Describe what you expected._")
        output += "\n\n## Actual behavior\n\n"
        output += section(actual, placeholder: "_Describe what happened instead._")

        let environment = environmentPreview
        if !environment.isEmpty {
            output += "\n\n## Environment\n\n"
            output += environment.split(separator: "\n").map { "- \($0)" }.joined(separator: "\n")
        }

        if !attachmentNames.isEmpty {
            output += "\n\n## Attachments\n\n"
            output += attachmentNames.map { "- `\($0)`" }.joined(separator: "\n")
            output += "\n\n> These files are saved next to this report on your Mac. "
            output += "Snaplet has not uploaded them anywhere — drag them into the issue after you create it."
        }
        return output + "\n"
    }

    private func section(_ text: String, placeholder: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }

    /// Turns numbered markers from the editor into a starting point for the
    /// "steps to reproduce" field.
    static func stepDraft(markerCount: Int) -> String {
        guard markerCount > 0 else { return "" }
        return (1...markerCount).map { "\($0). " }.joined(separator: "\n")
    }
}
