import Foundation

/// 解析 nettop 的进程汇总 CSV。字段按表头定位，进程标识从最后一个点之后读取。
enum NetworkCSV {
    static func parse(_ text: String) throws -> [Int32: NetworkByteCount] {
        var result: [Int32: NetworkByteCount] = [:]
        var receivedIndex: Int?
        var sentIndex: Int?
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = try columns(String(line))
            if fields.contains("bytes_in"), fields.contains("bytes_out") {
                receivedIndex = fields.firstIndex(of: "bytes_in")
                sentIndex = fields.firstIndex(of: "bytes_out")
                continue
            }
            guard let receivedIndex, let sentIndex else { throw ParseError.missingHeader }
            guard let label = fields.first, !label.isEmpty else { continue }
            guard let suffix = label.split(separator: ".").last, let pid = Int32(suffix), pid > 1,
                  fields.indices.contains(receivedIndex), fields.indices.contains(sentIndex),
                  let received = UInt64(fields[receivedIndex]), let sent = UInt64(fields[sentIndex]),
                  result[pid] == nil else { throw ParseError.invalidRow }
            result[pid] = NetworkByteCount(received: received, sent: sent)
        }
        guard receivedIndex != nil, sentIndex != nil else { throw ParseError.missingHeader }
        return result
    }

    private static func columns(_ line: String) throws -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" {
                    field.append("\""); index += 1
                } else { quoted.toggle() }
            } else if character == "," && !quoted {
                fields.append(field); field = ""
            } else { field.append(character) }
            index += 1
        }
        guard !quoted else { throw ParseError.invalidRow }
        fields.append(field)
        return fields
    }

    enum ParseError: Error { case missingHeader, invalidRow }
}

/// 每个完整进程身份有独立基线，避免 PID 复用、计数回退与空闲间隔产生虚假速度。
struct NetworkRateSampler {
    private var previous: [ProcessIdentity: NetworkByteCount] = [:]
    private var sampledAt: UInt64?

    mutating func reset() { previous.removeAll(); sampledAt = nil }

    mutating func sample(_ apps: [AppReading], counters: [Int32: NetworkByteCount], now: UInt64) -> NetworkRates {
        let elapsed = sampledAt.map { Double(now >= $0 ? now - $0 : 0) / NativeProcess.ticksPerSecond }
        var next: [ProcessIdentity: NetworkByteCount] = [:]
        var readings: [String: NetworkReading] = [:]
        var processes: [ProcessIdentity: NetworkReading] = [:]
        for app in apps {
            var received = 0.0, sent = 0.0
            var members = 0, comparable = 0
            for process in app.samples {
                guard let current = counters[process.identity.pid] else { continue }
                next[process.identity] = current
                members += 1
                processes[process.identity] = NetworkReading(receiveRate: nil, sendRate: nil, sampledProcesses: 1)
                if let elapsed, elapsed > 0, elapsed <= 20,
                   let old = previous[process.identity],
                   current.received >= old.received, current.sent >= old.sent {
                    received += Double(current.received - old.received) / elapsed
                    sent += Double(current.sent - old.sent) / elapsed
                    comparable += 1
                    processes[process.identity] = NetworkReading(receiveRate: Double(current.received - old.received) / elapsed,
                        sendRate: Double(current.sent - old.sent) / elapsed, sampledProcesses: 1)
                }
            }
            readings[app.id] = NetworkReading(receiveRate: comparable > 0 ? received : nil,
                                             sendRate: comparable > 0 ? sent : nil, sampledProcesses: members)
        }
        previous = next
        sampledAt = now
        return NetworkRates(applications: readings, processes: processes)
    }
}
