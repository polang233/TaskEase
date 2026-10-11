#include "TemperatureBridge.h"
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

/* AppleSMC 非公开的只读协议：80 字节消息，仅使用读元数据和读值操作。 */
static uint32_t code(const char *key) {
    return (uint32_t)(uint8_t)key[0] << 24 | (uint32_t)(uint8_t)key[1] << 16 |
           (uint32_t)(uint8_t)key[2] << 8 | (uint8_t)key[3];
}

static int request(io_connect_t connection, const char *key, uint8_t operation,
                   uint32_t data_size, uint8_t response[80]) {
    uint8_t input[80] = {0};
    uint32_t identifier = code(key);
    memcpy(input, &identifier, 4);
    memcpy(input + 28, &data_size, 4);
    input[42] = operation;
    size_t length = 80;
    memset(response, 0, 80);
    return IOConnectCallStructMethod(connection, 2, input, sizeof(input), response, &length) == KERN_SUCCESS &&
           length == 80 && response[40] == 0;
}

static double read_temperature(io_connect_t connection, const char *key) {
    uint8_t metadata[80], value[80];
    if (!request(connection, key, 9, 0, metadata)) return -1;
    uint32_t size = 0, type = 0;
    memcpy(&size, metadata + 28, 4);
    memcpy(&type, metadata + 32, 4);
    if (!((type == code("flt ") && size == 4) || (type == code("sp78") && size == 2)) ||
        !request(connection, key, 5, size, value)) return -1;
    double degrees;
    if (type == code("flt ")) {
        float raw = 0;
        memcpy(&raw, value + 48, sizeof(raw));
        degrees = raw;
    } else {
        int16_t raw = (int16_t)((uint16_t)value[48] << 8 | value[49]);
        degrees = raw / 256.0;
    }
    return isfinite(degrees) && degrees > 0 && degrees <= 130 ? degrees : -1;
}

/* 只报告可读芯片传感器的最高值，不推断单个核心位置；访问失败返回 -1。 */
double te_chip_temperature(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    io_connect_t connection = 0;
    kern_return_t opened = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (opened != KERN_SUCCESS) return -1;
    static const char *keys[] = {
        "Tp01", "Tp04", "Tp05", "Tp08", "Tp09", "Tp0C", "Tp0D", "Tp0G", "Tp0H", "Tp0K", "Tp0L",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0c", "Tp0d", "Tp0g", "Tp0h", "Tp0j", "Tp0m", "Tp0p", "Tp0r", "Tp0t", "Tp0u", "Tp0y",
        "Tp1b", "Tp1f", "Tp1h", "Tp1i", "Tp1j", "Tp1k", "Tp1l", "Tp1m", "Tp1n", "Tp1o", "Tp1p", "Tp1t",
        "Tg05", "Tg0D", "Tg0L", "Tg0U", "Tg0X", "Tg0d", "Tg0e", "Tg0f", "Tg0g", "Tg0h", "Tg0j",
        "Tg1Y", "Tg1c", "Tg1g"
    };
    double highest = -1;
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        double value = read_temperature(connection, keys[i]);
        if (value > highest) highest = value;
    }
    IOServiceClose(connection);
    return highest;
}
