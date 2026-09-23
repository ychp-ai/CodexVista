import CryptoKit
import Darwin
import Foundation

enum CodexSourceKind: String, Codable, Sendable {
    case cli
    case desktop
    case unknown
}

enum PlanKind: String, Codable, Sendable {
    case free
    case plus
    case proLite
    case pro20x
}

struct ProjectIdentity: Equatable, Sendable {
    let id: String
    let name: String
    let repositoryID: String?

    init(id: String, name: String, repositoryID: String? = nil) {
        self.id = id
        self.name = name
        self.repositoryID = repositoryID
    }

    static let unknown = ProjectIdentity(id: "unknown", name: "未识别项目")

    static func resolve(cwd: String?) -> ProjectIdentity? {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else { return nil }
        let standardizedPath = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let name = URL(fileURLWithPath: standardizedPath).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "/" else { return nil }
        let id = SHA256.hash(data: Data(standardizedPath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return ProjectIdentity(id: id, name: name)
    }

    func associating(repositoryID: String?) -> ProjectIdentity {
        ProjectIdentity(id: id, name: name, repositoryID: repositoryID)
    }
}

struct WorkspaceIdentity: Equatable, Sendable {
    private static let legacyUnknownName = "未识别工作区"
    private static let unknownName = "未识别项目"

    let id: String
    let name: String
    let rootCount: Int
    let isInferred: Bool

    init(id: String, name: String, rootCount: Int, isInferred: Bool = false) {
        self.id = id
        self.name = name == Self.legacyUnknownName ? Self.unknownName : name
        self.rootCount = rootCount
        self.isInferred = isInferred
    }

    static let unknown = WorkspaceIdentity(
        id: "unknown",
        name: unknownName,
        rootCount: 0,
        isInferred: false
    )

    static func resolve(
        rootPaths: [String]?,
        repositoryIDsByRootPath: [String: String] = [:],
        fallbackSingletonRepositoryID: String? = nil,
        displayName: String? = nil
    ) -> WorkspaceIdentity? {
        let roots = Array(Set((rootPaths ?? []).compactMap { rawPath -> String? in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        })).sorted()
        guard !roots.isEmpty else { return nil }

        var normalizedRepositoryIDs: [String: String] = [:]
        for (path, repositoryID) in repositoryIDsByRootPath {
            normalizedRepositoryIDs[
                URL(fileURLWithPath: path).standardizedFileURL.path
            ] = repositoryID
        }
        let rootIDs = roots.map { path -> String in
            if let repositoryID = normalizedRepositoryIDs[path], !repositoryID.isEmpty {
                return "repository:\(repositoryID)"
            }
            if roots.count == 1,
               let fallbackSingletonRepositoryID,
               !fallbackSingletonRepositoryID.isEmpty {
                return "repository:\(fallbackSingletonRepositoryID)"
            }
            let pathID = SHA256.hash(data: Data(path.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            return "path:\(pathID)"
        }
        let canonical = "workspace-v2|" + rootIDs.sorted().joined(separator: "|")
        let id = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let names = roots.map {
            URL(fileURLWithPath: $0).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let preferredName = displayName?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let name = if let preferredName, !preferredName.isEmpty {
            String(preferredName.prefix(120))
        } else {
            names.isEmpty ? unknownName : names.joined(separator: " + ")
        }
        return WorkspaceIdentity(
            id: id,
            name: name,
            rootCount: roots.count,
            isInferred: false
        )
    }

    static func inferFromProject(_ project: ProjectIdentity?) -> WorkspaceIdentity? {
        guard let project, project != .unknown else { return nil }
        let canonical = "workspace-cwd-inference-v1|\(project.id)"
        let id = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return WorkspaceIdentity(
            id: id,
            name: project.name,
            rootCount: 1,
            isInferred: true
        )
    }
}

struct WorkspaceDirectory: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
}

struct StoredWorkspaceConfiguration: Equatable, Sendable {
    let id: String
    let name: String
    let directories: [WorkspaceDirectory]
    let updatedAtMilliseconds: Int64

    var identity: WorkspaceIdentity {
        WorkspaceIdentity(id: id, name: name, rootCount: directories.count)
    }
}

struct SessionMetadata: Equatable, Sendable {
    let threadID: String
    let source: CodexSourceKind
    let formatVersion: String
    let project: ProjectIdentity?
    let workingDirectory: String?

    init(
        threadID: String,
        source: CodexSourceKind,
        formatVersion: String,
        project: ProjectIdentity? = nil,
        workingDirectory: String? = nil
    ) {
        self.threadID = threadID
        self.source = source
        self.formatVersion = formatVersion
        self.project = project
        self.workingDirectory = workingDirectory
    }
}

protocol RepositoryIdentityResolving: Sendable {
    func repositoryID(forWorkingDirectory workingDirectory: String) -> String?
}

// Background imports only use repository metadata already present in Codex records.
// Inspecting recorded working directories can trigger macOS Files and Folders prompts.
struct CodexMetadataRepositoryIdentityResolver: RepositoryIdentityResolving {
    func repositoryID(forWorkingDirectory workingDirectory: String) -> String? { nil }
}

struct GitRepositoryIdentityResolver: RepositoryIdentityResolving {
    private let executableURL: URL
    private let commandTimeout: DispatchTimeInterval

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        commandTimeout: DispatchTimeInterval = .seconds(2)
    ) {
        self.executableURL = executableURL
        self.commandTimeout = commandTimeout
    }

    static func repositoryID(repositoryURL: String?) -> String? {
        guard var normalized = repositoryURL?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else { return nil }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.hasSuffix(".git") { normalized.removeLast(4) }
        return fingerprint("git-repository-v1|remote|\(normalized)")
    }

    func repositoryID(forWorkingDirectory workingDirectory: String) -> String? {
        let directory = URL(fileURLWithPath: workingDirectory).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              runGit(["-C", directory.path, "rev-parse", "--is-inside-work-tree"]) == "true" else {
            return nil
        }

        if let repositoryID = Self.repositoryID(repositoryURL: runGit([
            "-C", directory.path, "config", "--get", "remote.origin.url"
        ])) {
            return repositoryID
        }
        let rootCommit = runGit(["-C", directory.path, "rev-list", "--max-parents=0", "HEAD"])?
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .sorted()
            .joined(separator: ",")

        let canonical: String?
        if let rootCommit, !rootCommit.isEmpty {
            canonical = "git-repository-v1|roots|\(rootCommit)"
        } else if let commonDirectory = runGit([
            "-C", directory.path, "rev-parse", "--path-format=absolute", "--git-common-dir"
        ]), !commonDirectory.isEmpty {
            canonical = "git-repository-v1|common|\(commonDirectory)"
        } else {
            canonical = nil
        }

        guard let canonical else { return nil }
        return Self.fingerprint(canonical)
    }

    private static func fingerprint(_ canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        let standardOutput = Pipe()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        guard completion.wait(timeout: .now() + commandTimeout) == .success else {
            process.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TurnContext: Equatable, Sendable {
    let turnID: String
    let model: String
    let workspace: WorkspaceIdentity?
    let workspaceRootPaths: [String]?

    init(
        turnID: String,
        model: String,
        workspace: WorkspaceIdentity?,
        workspaceRootPaths: [String]? = nil
    ) {
        self.turnID = turnID
        self.model = model
        self.workspace = workspace
        self.workspaceRootPaths = workspaceRootPaths
    }
}

struct PlanResolution: Equatable, Sendable {
    let kind: PlanKind
    let rawValue: String?
    let isInferred: Bool
}

struct TokenCounters: Equatable, Sendable {
    let input: Int64
    let cachedInput: Int64
    let output: Int64
    let reasoning: Int64
}

struct RawQuotaWindow: Equatable, Sendable {
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAtSeconds: Int64?
}

struct TokenCounterSnapshot: Equatable, Sendable {
    let observedAtMilliseconds: Int64
    let counters: TokenCounters?
    let planRaw: String?
    let quotas: [RawQuotaWindow]
}

enum SessionLifecycleKind: String, Codable, Sendable {
    case started
    case completed
    case interrupted
    case rolledBack
}

struct SessionLifecycleEvent: Equatable, Sendable {
    let kind: SessionLifecycleKind
    let observedAtMilliseconds: Int64
    let turnID: String?
}

enum ActivityKind: String, Codable, Sendable {
    case skill
    case tool
}

struct ActivityCallSnapshot: Equatable, Sendable {
    let observedAtMilliseconds: Int64
    let callID: String?
    let toolNames: [String]
    let skillNames: [String]
}

enum CodexDecodedEvent: Equatable, Sendable {
    case session(SessionMetadata)
    case turn(TurnContext)
    case token(TokenCounterSnapshot)
    case lifecycle(SessionLifecycleEvent)
    case activity(ActivityCallSnapshot)
}
