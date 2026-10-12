#ifndef TASK_EASE_PROCESS_BRIDGE_H
#define TASK_EASE_PROCESS_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
    int32_t pid;
    int32_t parentPid;
    uint32_t uid;
    uint32_t status;
    uint64_t startSeconds;
    uint64_t startMicroseconds;
    uint64_t cpuTicks;
    uint64_t physicalBytes;
    uint64_t diskReadBytes;
    uint64_t diskWriteBytes;
    uint64_t interruptWakeups;
} TEProcessStats;
typedef struct { uint64_t user, system, idle, nice; } TECPUTicks;
int te_list_pids(int32_t *pids, int bytes);
int te_process_identity(int32_t pid, TEProcessStats *result);
int te_process_stats(int32_t pid, TEProcessStats *result);
int te_process_path(int32_t pid, char *buffer, uint32_t length);
uint64_t te_now(void);
double te_ticks_per_second(void);
int te_set_background(int32_t pid, uint64_t seconds, uint64_t microseconds, int enabled);
int te_get_background(int32_t pid);
int te_signal_process(int32_t pid, uint64_t seconds, uint64_t microseconds, int signal_number);
int te_cpu_ticks(TECPUTicks *result);
typedef struct { int32_t pid; uint64_t gpuNanoseconds; } TEProcessGPU;
double te_gpu_percent(void);
int te_gpu_process_times(TEProcessGPU *results, int capacity);
int te_gpu_info(char *model, uint32_t length, int32_t *cores);
void te_install_worker_signals(void);
int te_worker_should_exit(void);
#endif
