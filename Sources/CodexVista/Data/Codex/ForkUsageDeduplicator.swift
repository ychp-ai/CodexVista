import CryptoKit
import Foundation

enum UsageEventIdentity {
    static func fingerprint(threadID: String, segment: Int64, counters: TokenCounters) -> String {
        let value = "usage-v2|\(threadID)|\(segment)|\(counters.input)|\(counters.cachedInput)|\(counters.output)|\(counters.reasoning)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Older forks can copy usage under the child's ID and rewrite all timestamps.
/// Only explicit fork ancestors with matching counters, segment and compatible turn
/// provide evidence of a copy. Ordinary subagent relationships are not sufficient.
struct ForkUsageDeduplicator {
    private var headerCache: [String: (file: RolloutFile, header: Header?)] = [:]
    private var snapshotCache: [String: (file: RolloutFile, snapshots: [Snapshot])] = [:]

    mutating func copiedFingerprints(in files: [RolloutFile]) throws -> [String: String] {
        let fileIDs = Set(files.map(\.fileID))
        headerCache = headerCache.filter { fileIDs.contains($0.key) }
        snapshotCache = snapshotCache.filter { fileIDs.contains($0.key) }
        var headers: [String: Header] = [:]
        for file in files {
            if headerCache[file.fileID]?.file != file {
                headerCache[file.fileID] = (file, try? readHeader(file.url))
            }
            if let header = headerCache[file.fileID]?.header {
                headers[header.id] = header
            }
        }

        var ancestors: [String: [(id: String, cutoff: Int64)]] = [:]
        for header in headers.values where header.forkedFromID != nil {
            var chain: [(id: String, cutoff: Int64)] = []
            var seen: Set<String> = [header.id]
            var current = header
            var cutoff = Int64.max
            while let parent = current.forkedFromID, let createdAt = current.createdAt {
                guard seen.insert(parent).inserted else { chain = []; break }
                cutoff = min(cutoff, createdAt)
                chain.append((parent, cutoff))
                guard let next = headers[parent] else { break }
                current = next
            }
            if !chain.isEmpty { ancestors[header.id] = chain }
        }
        guard !ancestors.isEmpty else { return [:] }
        let related = Set(ancestors.keys).union(ancestors.values.flatMap { $0.map(\.id) })
        var snapshots: [String: [String: Snapshot]] = [:]
        for file in files {
            guard let header = headerCache[file.fileID]?.header, related.contains(header.id) else { continue }
            if snapshotCache[file.fileID]?.file != file {
                snapshotCache[file.fileID] = (file, try readSnapshots(file.url))
            }
            for snapshot in snapshotCache[file.fileID]?.snapshots ?? [] {
                if let existing = snapshots[snapshot.threadID]?[snapshot.counterKey],
                   existing.observedAt <= snapshot.observedAt { continue }
                snapshots[snapshot.threadID, default: [:]][snapshot.counterKey] = snapshot
            }
        }

        var copies: [String: String] = [:]
        for (child, chain) in ancestors {
            guard let childSnapshots = snapshots[child] else { continue }
            for snapshot in childSnapshots.values {
                // Prefer the oldest ancestor, so a chain of copies never deletes its survivor.
                for ancestor in chain.reversed() {
                    guard let original = snapshots[ancestor.id]?[snapshot.counterKey],
                          original.observedAt <= ancestor.cutoff,
                          snapshot.turnID == nil || original.turnID == nil || snapshot.turnID == original.turnID
                    else { continue }
                    copies[snapshot.fingerprint] = original.fingerprint
                    break
                }
            }
        }
        return copies
    }

    private func readHeader(_ url: URL) throws -> Header? {
        let stream = try RolloutByteStream(url: url)
        var data = Data()
        // Metadata is the first line. Never read an unbounded body to find it.
        while data.count < 2 * 1_024 * 1_024 {
            guard let chunk = try stream.read(upToCount: 16 * 1_024) else { return nil }
            data.append(chunk)
            if let newline = data.firstIndex(of: 0x0A) {
                let envelope = try JSONDecoder().decode(HeaderEnvelope.self, from: data[..<newline])
                guard envelope.type == "session_meta" else { return nil }
                let payload = envelope.payload
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let timestamp = envelope.timestamp ?? payload.timestamp
                var date = timestamp.flatMap(formatter.date(from:))
                if date == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = timestamp.flatMap(formatter.date(from:))
                }
                return Header(id: payload.id, forkedFromID: payload.forkedFromID,
                              createdAt: date.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) })
            }
        }
        return nil
    }

    private func readSnapshots(_ url: URL) throws -> [Snapshot] {
        let batch = try IncrementalJSONLReader().read(file: url, fromOffset: 0)
        let decoder = CodexEventDecoder()
        var threadID: String?
        var turnID: String?
        var previous: TokenCounters?
        var segment: Int64 = 0
        var result: [Snapshot] = []
        for line in batch.lines {
            // Match the usage importer's boundary: activity payloads are neither
            // needed nor decoded for this reconciliation.
            if decoder.isResponseItem(line: line.data) { continue }
            // Stop at the same malformed line as the main importer.
            let event: CodexDecodedEvent?
            do { event = try decoder.decode(line: line.data) } catch { break }
            switch event {
            case .session(let metadata):
                if threadID != metadata.threadID {
                    previous = nil
                    segment = 0
                    turnID = nil
                }
                threadID = metadata.threadID
            case .turn(let turn):
                // Only historical turn_context identifies the copied usage turn.
                // Forks can rewrite task_started/task_complete IDs independently.
                turnID = turn.turnID
            case .token(let token):
                guard let threadID, let counters = token.counters else { continue }
                let baseline = previous ?? TokenCounters(input: 0, cachedInput: 0, output: 0, reasoning: 0)
                if previous != nil, counters.input < baseline.input || counters.cachedInput < baseline.cachedInput
                    || counters.output < baseline.output || counters.reasoning < baseline.reasoning {
                    segment += 1
                }
                if UsageAccumulator.delta(previous: baseline, current: counters) != nil {
                    result.append(Snapshot(threadID: threadID, turnID: turnID,
                        observedAt: token.observedAtMilliseconds, segment: segment, counters: counters))
                }
                previous = counters
            default: break
            }
        }
        return result
    }

    private struct Snapshot {
        let threadID: String
        let turnID: String?
        let observedAt: Int64
        let segment: Int64
        let counters: TokenCounters

        var counterKey: String {
            "\(segment)|\(counters.input)|\(counters.cachedInput)|\(counters.output)|\(counters.reasoning)"
        }
        var fingerprint: String {
            UsageEventIdentity.fingerprint(threadID: threadID, segment: segment, counters: counters)
        }
    }

    private struct Header {
        let id: String
        let forkedFromID: String?
        let createdAt: Int64?
    }

    private struct HeaderEnvelope: Decodable {
        let type: String
        let timestamp: String?
        let payload: Payload

        struct Payload: Decodable {
            let id: String
            let timestamp: String?
            let forkedFromID: String?

            enum CodingKeys: String, CodingKey {
                case id, timestamp
                case forkedFromID = "forked_from_id"
            }
        }
    }
}
