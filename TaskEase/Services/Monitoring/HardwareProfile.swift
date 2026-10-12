import Foundation
import Darwin

/// 芯片的静态描述，首次打开指标详情时读取一次并缓存；不常驻任何系统对象。
struct HardwareProfile: Sendable {
    struct Cluster: Sendable, Hashable {
        let name: String
        let cores: Int
    }

    let cpuModel: String?
    let physicalCores: Int
    let logicalCores: Int
    let clusters: [Cluster]
    let gpuModel: String?
    let gpuCores: Int?
    let memoryBytes: UInt64

    static let current = read()

    private static func read() -> HardwareProfile {
        let levels = integer("hw.nperflevels") ?? 0
        let clusters = (0..<levels).compactMap { level -> Cluster? in
            guard let cores = integer("hw.perflevel\(level).physicalcpu"), cores > 0 else { return nil }
            return Cluster(name: clusterName(string("hw.perflevel\(level).name")), cores: cores)
        }
        var model = [CChar](repeating: 0, count: 128)
        var gpuCores: Int32 = 0
        let gpu = te_gpu_info(&model, UInt32(model.count), &gpuCores) != 0
        return HardwareProfile(cpuModel: string("machdep.cpu.brand_string"),
                               physicalCores: integer("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount,
                               logicalCores: ProcessInfo.processInfo.processorCount,
                               clusters: clusters,
                               gpuModel: gpu ? text(model) : nil,
                               gpuCores: gpuCores > 0 ? Int(gpuCores) : nil,
                               memoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    /// 系统给出的簇名称换成中文；新芯片出现未知名称时原样显示。
    private static func clusterName(_ raw: String?) -> String {
        switch raw {
        case "Super": "超级核"
        case "Performance": "性能核"
        case "Efficiency": "能效核"
        case let value?: value
        case nil: "核心"
        }
    }

    private static func text(_ buffer: [CChar]) -> String? {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).nonEmpty
    }

    private static func integer(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    private static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return text(buffer)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
