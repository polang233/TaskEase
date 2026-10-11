import Foundation
import Testing
@testable import TaskEase

/// 覆盖网卡差分边界、内存口径与数值配色，不依赖真实网速或传感器温度。
struct SystemMetricsTests {
    @Test func interfaceRatesUseIndependentBaselinesAndReset() {
        var sampler = SystemNetworkSampler()
        let second = UInt64(NativeProcess.ticksPerSecond)
        let first = sampler.sample([.init(index: 1, received: 100, sent: 100)], now: second)
        #expect(first.receiveRate == nil)
        let next = sampler.sample([.init(index: 1, received: 500, sent: 300), .init(index: 2, received: 1_000_000, sent: 20)], now: second * 3)
        #expect(next.receiveRate == 200)
        #expect(next.sendRate == 100)
        let reset = sampler.sample([.init(index: 1, received: 10, sent: 10)], now: second * 4)
        #expect(reset.receiveRate == nil)
        let afterReset = sampler.sample([.init(index: 1, received: 30, sent: 50)], now: second * 5)
        #expect(afterReset.receiveRate == 20)
        #expect(afterReset.sendRate == 40)
        #expect(sampler.sample([.init(index: 1, received: 900, sent: 900)], now: second * 30).receiveRate == nil)
        #expect(sampler.sample([], now: second * 31).receiveRate == 0)
        #expect(sampler.sample([.init(index: 3, received: 900, sent: 900)], now: second * 32).receiveRate == nil)
        sampler.reset()
        #expect(sampler.sample([.init(index: 3, received: 1_000, sent: 1_000)], now: second * 33).receiveRate == nil)
    }

    @Test func memoryIncludesCompressionAndRejectsEmptyCapacity() {
        let reading = SystemMemoryReading(usedBytes: 50, totalBytes: 100, compressedBytes: 10)
        #expect(reading.percent == 50)
        #expect(SystemMemoryReading(usedBytes: 0, totalBytes: 0, compressedBytes: 0).percent == nil)
    }

    @Test func severityBoundariesAndApplicationCoreUnits() {
        #expect(MetricSeverity.utilization(nil) == .unknown)
        #expect(MetricSeverity.utilization(.nan) == .unknown)
        #expect(MetricSeverity.utilization(39.9) == .normal)
        #expect(MetricSeverity.utilization(40) == .elevated)
        #expect(MetricSeverity.utilization(60) == .high)
        #expect(MetricSeverity.utilization(80) == .critical)
        #expect(MetricSeverity.applicationCPU(100, coreCount: 8) == .normal)
        #expect(MetricSeverity.applicationCPU(800, coreCount: 8) == .critical)
        #expect(MetricSeverity.temperature(49.9) == .normal)
        #expect(MetricSeverity.temperature(50) == .elevated)
        #expect(MetricSeverity.temperature(70) == .high)
        #expect(MetricSeverity.temperature(85) == .critical)
    }

    @Test @MainActor func compactFormatsPreserveUnitsAndMissingValues() {
        #expect(Display.gigabytes(1_073_741_824) == "1.0")
        #expect(Display.megabytesPerSecond(1_234_567) == "1.23")
        #expect(Display.megabytesPerSecond(nil) == "—")
        #expect(Display.megabytesPerSecond(.infinity) == "—")
        #expect(Display.temperature(47.391) == "47.4°C")
    }
}
