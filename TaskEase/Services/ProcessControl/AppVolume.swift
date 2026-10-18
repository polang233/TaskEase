import Foundation
import CoreAudio

/// 按应用调整后台音量（macOS 14.2 起）。
/// 静音只创建静音截取；其他音量先截取并静音应用原声，再经私有聚合设备按增益播放到当前输出设备。
/// 截取与聚合设备都归本进程所有，本应用退出或崩溃时由系统销毁，应用声音随之恢复，无需恢复记录。
@MainActor
final class AppVolume {
    /// 实时音频线程读取的增益；只在主线程写入单个浮点数。
    private final class Gain: @unchecked Sendable {
        let value = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        init(_ gain: Float) { value.initialize(to: gain) }
        deinit { value.deallocate() }
    }

    private final class Session {
        let processes: [AudioObjectID]
        let tap: AudioObjectID
        /// 静音时为 nil，不需要播放。
        let outputUID: String?
        let gain: Gain
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?

        init(processes: [AudioObjectID], tap: AudioObjectID, outputUID: String?, gain: Float) {
            self.processes = processes; self.tap = tap; self.outputUID = outputUID; self.gain = Gain(gain)
        }
    }

    private var sessions: [String: Session] = [:]
    /// 创建失败的进程集合；同一组进程不重复尝试，进程变化或规则重新开启时再试。
    private var failures: [String: [AudioObjectID]] = [:]
    /// 调整失败（多为未授予系统录音权限）的应用，供规则编辑器提示。
    private(set) var failedIDs: Set<String> = []
    private let queue = DispatchQueue(label: "TaskEase.AppVolume", qos: .userInteractive)
    var onChange: (() -> Void)?

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { true } else { false }
    }

    /// 百分比转为播放增益：按平方映射，滑杆中段的响度变化更均匀。
    nonisolated static func gain(percent: Double) -> Float {
        let level = min(1, max(0, percent / 100))
        return Float(level * level)
    }

    /// 按应用传入进程与目标音量；不在列表中的应用立即恢复原声。
    func update(_ groups: [String: (pids: Set<Int32>, percent: Double)]) {
        guard Self.isSupported else { return }
        for id in Array(sessions.keys) where groups[id] == nil { remove(id) }
        failures = failures.filter { groups[$0.key] != nil }
        if !groups.isEmpty {
            // 只有使用过音频的进程才有对应对象；暂无对象的进程在下次检查时补上。
            let objects = Self.processObjects()
            let output = Self.defaultOutputUID()
            for (id, group) in groups {
                let processes = group.pids.compactMap { objects[$0] }.sorted()
                let gain = Self.gain(percent: group.percent)
                let outputUID = gain > 0 ? output : nil
                if let session = sessions[id], session.processes == processes, session.outputUID == outputUID {
                    session.gain.value.pointee = gain
                    continue
                }
                remove(id)
                guard !processes.isEmpty, failures[id] != processes else { continue }
                if gain > 0 && outputUID == nil { continue }
                if let session = Self.start(processes, outputUID: outputUID, gain: gain, queue: queue) {
                    sessions[id] = session
                    failures[id] = nil
                } else {
                    failures[id] = processes
                }
            }
        }
        let current = Set(failures.keys)
        if current != failedIDs { failedIDs = current; onChange?() }
    }

    /// 恢复所有应用的原声，并清除失败记录以便下次重新尝试。
    func stop() {
        for id in Array(sessions.keys) { remove(id) }
        failures.removeAll()
        if !failedIDs.isEmpty { failedIDs.removeAll(); onChange?() }
    }

    /// 清除失败记录，下次更新时重新尝试（例如授权之后）。
    func retry() { failures.removeAll() }

    private func remove(_ id: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        Self.stop(session)
    }

    private static func start(_ processes: [AudioObjectID], outputUID: String?, gain: Float,
                              queue: DispatchQueue) -> Session? {
        guard #available(macOS 14.2, *) else { return nil }
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "TaskEase"
        description.isPrivate = true
        description.muteBehavior = .muted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != kAudioObjectUnknown else { return nil }
        let session = Session(processes: processes, tap: tap, outputUID: outputUID, gain: gain)
        guard let outputUID else { return session }

        // 以输出设备为主设备、截取为输入，聚合设备的输入回调里按增益写回输出。
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "TaskEase Volume",
            kAudioAggregateDeviceUIDKey: "TaskEase.volume.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &session.aggregate) == noErr else {
            stop(session); return nil
        }
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, session.aggregate, queue, ioBlock(session.gain))
        guard status == noErr, let procID else { stop(session); return nil }
        session.procID = procID
        guard AudioDeviceStart(session.aggregate, procID) == noErr else { stop(session); return nil }
        return session
    }

    /// 回调在音频线程执行，必须在非隔离上下文中创建：在主线程隔离的方法里写闭包会继承主线程隔离，
    /// Swift 6 运行时检查到在音频线程调用就会直接终止进程。
    nonisolated private static func ioBlock(_ gain: Gain) -> AudioDeviceIOBlock {
        { @Sendable _, input, _, output, _ in
            mix(input, into: output, gain: gain.value.pointee)
        }
    }

    private static func stop(_ session: Session) {
        if let procID = session.procID {
            AudioDeviceStop(session.aggregate, procID)
            AudioDeviceDestroyIOProcID(session.aggregate, procID)
        }
        if session.aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(session.aggregate) }
        if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(session.tap) }
    }

    /// 实时线程中的混音：截取流位于输入末尾（立体声），写入输出的前两个声道，其余声道静音。不分配内存。
    nonisolated private static func mix(_ input: UnsafePointer<AudioBufferList>,
                                        into output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let source = stereo(inputs, fromEnd: true), let target = stereo(outputs, fromEnd: false) else { return }
        let frames = min(source.frames, target.frames)
        for frame in 0..<frames {
            target.left[frame * target.stride] = source.left[frame * source.stride] * gain
            target.right[frame * target.stride] = source.right[frame * source.stride] * gain
        }
    }

    private struct Stereo {
        let left: UnsafeMutablePointer<Float>
        let right: UnsafeMutablePointer<Float>
        let stride: Int
        let frames: Int
    }

    /// 从缓冲区列表取一对 Float32 声道，兼容交错与非交错布局；单声道时左右相同。
    nonisolated private static func stereo(_ list: UnsafeMutableAudioBufferListPointer, fromEnd: Bool) -> Stereo? {
        guard list.count > 0 else { return nil }
        let index = fromEnd ? list.count - 1 : 0
        let buffer = list[index]
        guard let data = buffer.mData, buffer.mNumberChannels > 0 else { return nil }
        let channels = Int(buffer.mNumberChannels)
        let base = data.assumingMemoryBound(to: Float.self)
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        if channels >= 2 {
            let offset = fromEnd ? channels - 2 : 0
            return Stereo(left: base + offset, right: base + offset + 1, stride: channels, frames: frames)
        }
        // 非交错：相邻两个单声道缓冲区组成立体声。
        let pairIndex = fromEnd ? index - 1 : index + 1
        if pairIndex >= 0, pairIndex < list.count, let pair = list[pairIndex].mData, list[pairIndex].mNumberChannels == 1 {
            let other = pair.assumingMemoryBound(to: Float.self)
            let otherFrames = Int(list[pairIndex].mDataByteSize) / MemoryLayout<Float>.size
            let (left, right) = fromEnd ? (other, base) : (base, other)
            return Stereo(left: left, right: right, stride: 1, frames: min(frames, otherFrames))
        }
        return Stereo(left: base, right: base, stride: 1, frames: frames)
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    /// 读取音频服务登记的进程对象，按 PID 建立对应关系。
    private static func processObjects() -> [Int32: AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [:] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [:] }
        var result: [Int32: AudioObjectID] = [:]
        var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        for object in objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
            var pid: pid_t = -1
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid > 0 {
                result[pid] = object
            }
        }
        return result
    }
}
