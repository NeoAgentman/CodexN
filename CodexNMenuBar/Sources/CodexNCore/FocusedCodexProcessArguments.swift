import Foundation

#if os(macOS)
import Darwin
#endif

public enum FocusedCodexProcessArgumentsParser {
    public static func parse(_ data: Data) -> (arguments: [String], environment: [String: String]) {
        let bytes = [UInt8](data)
        guard bytes.count >= MemoryLayout<Int32>.size else { return ([], [:]) }

        let argc = Int(readInt32(from: bytes))
        var offset = MemoryLayout<Int32>.size

        _ = readNullTerminatedString(from: bytes, offset: &offset)
        skipNulls(in: bytes, offset: &offset)

        var arguments: [String] = []
        if argc > 0 {
            for _ in 0..<argc {
                guard let argument = readNullTerminatedString(from: bytes, offset: &offset) else { break }
                arguments.append(argument)
            }
        }

        var environment: [String: String] = [:]
        while offset < bytes.count {
            skipNulls(in: bytes, offset: &offset)
            guard let entry = readNullTerminatedString(from: bytes, offset: &offset), !entry.isEmpty else { continue }
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            environment[key] = value
        }

        return (arguments, environment)
    }

    private static func readInt32(from bytes: [UInt8]) -> Int32 {
        var value: Int32 = 0
        withUnsafeMutableBytes(of: &value) { destination in
            for index in 0..<min(destination.count, bytes.count) {
                destination[index] = bytes[index]
            }
        }
        return value
    }

    private static func readNullTerminatedString(from bytes: [UInt8], offset: inout Int) -> String? {
        guard offset < bytes.count else { return nil }
        let start = offset
        while offset < bytes.count, bytes[offset] != 0 {
            offset += 1
        }
        let value = String(data: Data(bytes[start..<offset]), encoding: .utf8) ?? ""
        if offset < bytes.count {
            offset += 1
        }
        return value
    }

    private static func skipNulls(in bytes: [UInt8], offset: inout Int) {
        while offset < bytes.count, bytes[offset] == 0 {
            offset += 1
        }
    }
}

public enum FocusedCodexProcessArgumentsReader {
    public static func read(pid: Int32) -> (arguments: [String], environment: [String: String]) {
        #if os(macOS)
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return ([], [:])
        }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return ([], [:]) }

        if size < data.count {
            data = data.prefix(size)
        }
        return FocusedCodexProcessArgumentsParser.parse(data)
        #else
        return ([], [:])
        #endif
    }
}
