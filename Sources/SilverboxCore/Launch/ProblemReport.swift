import Foundation

/// A problem report as a new GitHub issue: Help › Report a Problem… opens the
/// issue form in the browser, with headings for the user to fill in and, at
/// the end, the facts the maintainer needs about the app, the Mac, the
/// collections and the emulators. Nothing is sent until the user submits the
/// form. Help › Send Feedback… opens a new discussion instead, for comments
/// and ideas.
nonisolated public enum ProblemReport {
    public static let repository = URL(string: "https://github.com/SilvercodeStudio/Silverbox")!

    /// What the report says about this Mac. No paths, so no user names.
    public struct Details: Sendable, Equatable {
        /// "Silverbox 0.3 (4) · 536e697".
        public var program: String
        /// "macOS 26.2 (Build 25C56), Mac15,8, Apple silicon".
        public var system: String
        /// One line per collection: "eXoDOS, eXoWin3x: 8,433 games".
        public var collections: [String]
        /// One line per emulator found: "DOSBox Staging (FluidSynth)".
        public var emulators: [String]

        public init(program: String, system: String = ProblemReport.system, collections: [String], emulators: [String])
        {
            self.program = program
            self.system = system
            self.collections = collections
            self.emulators = emulators
        }
    }

    /// The issue's text: the headings to fill in, then the details.
    public static func issueBody(_ details: Details) -> String {
        func list(_ items: [String]) -> String {
            items.isEmpty ? " none" : "\n" + items.map { "- \($0)" }.joined(separator: "\n")
        }
        return """
            ### What happened


            ### What you expected


            ### How to make it happen again


            <!-- For a game that does not start, right-click it, choose Show Last Launch Log…, \
            click Copy as Markdown, and paste the report here. -->

            ---
            \(details.program)
            \(details.system)
            Collections:\(list(details.collections))
            Emulators:\(list(details.emulators))
            """
    }

    /// The new issue's page, filled in.
    public static func issueURL(_ details: Details) -> URL {
        page("issues/new", query: [URLQueryItem(name: "body", value: issueBody(details))])
    }

    /// The text of a new discussion: room for the comment, then the program and the system.
    public static func feedbackBody(program: String, system: String = system) -> String {
        """


        <!-- Comments, ideas and questions are welcome here. For a problem, use Help › Report a \
        Problem… instead. -->

        ---
        \(program)
        \(system)
        """
    }

    /// A new discussion's page in the General category, filled in. The
    /// repository must have Discussions on.
    public static func feedbackURL(program: String, system: String = system) -> URL {
        page(
            "discussions/new",
            query: [
                URLQueryItem(name: "category", value: "general"),
                URLQueryItem(name: "body", value: feedbackBody(program: program, system: system)),
            ])
    }

    private static func page(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: repository.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        return components.url!
    }

    /// "macOS 26.2 (Build 25C56), Mac15,8, Apple silicon".
    public static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(
            of: "Version ", with: "")
        #if os(macOS)
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var bytes = [UInt8](repeating: 0, count: max(size, 1))
            sysctlbyname("hw.model", &bytes, &size, nil, 0)
            // The name ends at its null byte.
            let model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            let name = "macOS \(version)"
            #if arch(arm64)
                let architecture = "Apple silicon"
            #else
                let architecture = "Intel"
            #endif
        #else
            let (model, name, architecture) = ("", version, "")
        #endif
        return [name, model, architecture].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
