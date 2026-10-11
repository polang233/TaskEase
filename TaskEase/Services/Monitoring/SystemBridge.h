#ifndef TASK_EASE_SYSTEM_BRIDGE_H
#define TASK_EASE_SYSTEM_BRIDGE_H
#include <stdint.h>
typedef struct {
    uint64_t totalBytes;
    uint64_t usedBytes;
    uint64_t compressedBytes;
} TESystemMemory;
typedef struct {
    uint32_t interfaceIndex;
    uint64_t receivedBytes;
    uint64_t sentBytes;
} TESystemNetwork;
int te_system_memory(TESystemMemory *result);
int te_system_network(TESystemNetwork *results, int capacity);
#endif
