import Foundation
import CZstd

/// Shared streaming input. Offsets and caller limits always refer to decoded bytes.
/// Compressed sources are never expanded to disk and never need an external executable.
final class RolloutByteStream {
    private let handle: FileHandle
    private var decoder: OpaquePointer?
    private var input = Data()
    private var inputPosition = 0
    private var sourceEnded = false
    private var remainingHint = 1

    static func isCompressed(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".jsonl.zst")
    }

    static func isRollout(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" || isCompressed(url)
    }

    static func uncompressedURL(_ url: URL) -> URL {
        isCompressed(url) ? url.deletingPathExtension() : url
    }

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        if Self.isCompressed(url) {
            guard let stream = ZSTD_createDStream() else {
                throw RolloutStreamError.decoderUnavailable
            }
            decoder = stream
            guard ZSTD_isError(ZSTD_initDStream(stream)) == 0,
                  ZSTD_isError(ZSTD_DCtx_setParameter(stream, ZSTD_d_windowLogMax, 27)) == 0 else {
                throw RolloutStreamError.invalidCompressedData
            }
        }
    }

    deinit {
        if let decoder { ZSTD_freeDStream(decoder) }
        try? handle.close()
    }

    /// Called once on a newly opened stream. A zstd offset is reached by decoding/discarding.
    func seek(to offset: Int64) throws -> Bool {
        if decoder == nil {
            guard try handle.seekToEnd() >= UInt64(offset) else { return false }
            try handle.seek(toOffset: UInt64(offset))
            return true
        }
        var remaining = offset
        while remaining > 0 {
            guard let chunk = try read(upToCount: Int(min(remaining, 64 * 1_024))) else { return false }
            remaining -= Int64(chunk.count)
        }
        return true
    }

    func read(upToCount count: Int) throws -> Data? {
        guard count > 0 else { throw IncrementalJSONLReaderError.invalidChunkSize(count) }
        try Task.checkCancellation()
        guard let decoder else { return try handle.read(upToCount: count) }
        var output = Data(count: count)
        while true {
            try Task.checkCancellation()
            if inputPosition == input.count, !sourceEnded {
                input = try handle.read(upToCount: 64 * 1_024) ?? Data()
                inputPosition = 0
                sourceEnded = input.isEmpty
            }
            if sourceEnded, remainingHint == 0 { return nil }
            var written = 0
            let previousPosition = inputPosition
            let hint = input.withUnsafeBytes { source in
                output.withUnsafeMutableBytes { destination in
                    var sourceBuffer = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: inputPosition)
                    var destinationBuffer = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                    let result = ZSTD_decompressStream(decoder, &destinationBuffer, &sourceBuffer)
                    inputPosition = sourceBuffer.pos
                    written = destinationBuffer.pos
                    return result
                }
            }
            guard ZSTD_isError(hint) == 0 else { throw RolloutStreamError.invalidCompressedData }
            remainingHint = hint
            if written > 0 {
                output.count = written
                return output
            }
            if sourceEnded {
                guard hint == 0 else { throw RolloutStreamError.incompleteCompressedData }
                return nil
            }
            guard inputPosition > previousPosition else { throw RolloutStreamError.invalidCompressedData }
        }
    }
}

enum RolloutStreamError: Error {
    case decoderUnavailable
    case invalidCompressedData
    case incompleteCompressedData
}

struct JSONLLine: Equatable, Sendable {
    let data: Data
    let endOffset: Int64
}

struct JSONLReadBatch: Equatable, Sendable {
    let lines: [JSONLLine]
    let committedOffset: Int64
    let wasTruncated: Bool
}

enum IncrementalJSONLReaderError: Error, Equatable {
    case invalidChunkSize(Int)
    case invalidOffset(Int64)
    case invalidFileSize
    case offsetOverflow
}

struct IncrementalJSONLReader: Sendable {
    private let chunkSize: Int

    init(chunkSize: Int = 64 * 1_024) {
        self.chunkSize = chunkSize
    }

    func read(file url: URL, fromOffset requestedOffset: Int64) throws -> JSONLReadBatch {
        guard chunkSize > 0 else {
            throw IncrementalJSONLReaderError.invalidChunkSize(chunkSize)
        }
        guard requestedOffset >= 0 else {
            throw IncrementalJSONLReaderError.invalidOffset(requestedOffset)
        }

        let stream = try RolloutByteStream(url: url)
        guard try stream.seek(to: requestedOffset) else {
            return JSONLReadBatch(lines: [], committedOffset: 0, wasTruncated: true)
        }

        var lines: [JSONLLine] = []
        var pending = Data()
        var absoluteChunkStart = requestedOffset
        var committedOffset = requestedOffset

        while let chunk = try stream.read(upToCount: chunkSize), !chunk.isEmpty {
            var segmentStart = chunk.startIndex

            for index in chunk.indices where chunk[index] == 0x0A {
                pending.append(contentsOf: chunk[segmentStart..<index])
                let bytesThroughNewline = chunk.distance(from: chunk.startIndex, to: index) + 1
                let (endOffset, overflow) = absoluteChunkStart.addingReportingOverflow(Int64(bytesThroughNewline))
                guard !overflow else { throw IncrementalJSONLReaderError.offsetOverflow }

                lines.append(JSONLLine(data: pending, endOffset: endOffset))
                committedOffset = endOffset
                pending.removeAll(keepingCapacity: true)
                segmentStart = chunk.index(after: index)
            }

            pending.append(contentsOf: chunk[segmentStart..<chunk.endIndex])
            let (nextChunkStart, overflow) = absoluteChunkStart.addingReportingOverflow(Int64(chunk.count))
            guard !overflow else { throw IncrementalJSONLReaderError.offsetOverflow }
            absoluteChunkStart = nextChunkStart
        }

        return JSONLReadBatch(
            lines: lines,
            committedOffset: committedOffset,
            wasTruncated: false
        )
    }
}
