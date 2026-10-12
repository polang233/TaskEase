#include "ProcessBridge.h"
#include <libproc.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>

int te_list_pids(int32_t *pids, int bytes) { return proc_listallpids(pids, bytes); }
int te_process_identity(int32_t pid, TEProcessStats *out) {
    struct proc_bsdinfo b = {0};
    if (pid <= 1 || proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &b, sizeof(b)) != sizeof(b)) return 0;
    memset(out, 0, sizeof(*out));
    out->pid = pid; out->parentPid = b.pbi_ppid; out->uid = b.pbi_uid;
    out->status = b.pbi_status; out->startSeconds = b.pbi_start_tvsec;
    out->startMicroseconds = b.pbi_start_tvusec;
    return 1;
}
int te_process_stats(int32_t pid, TEProcessStats *out) {
    struct rusage_info_v4 r = {0};
    if (!te_process_identity(pid, out) ||
        proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&r) != 0) return 0;
    out->cpuTicks = r.ri_user_time + r.ri_system_time;
    out->physicalBytes = r.ri_phys_footprint;
    out->diskReadBytes = r.ri_diskio_bytesread; out->diskWriteBytes = r.ri_diskio_byteswritten;
    out->interruptWakeups = r.ri_interrupt_wkups;
    return 1;
}
int te_process_path(int32_t pid, char *buffer, uint32_t length) {
    return proc_pidpath(pid, buffer, length);
}
uint64_t te_now(void) { return mach_absolute_time(); }
double te_ticks_per_second(void) {
    mach_timebase_info_data_t t; mach_timebase_info(&t);
    return 1e9 * t.denom / t.numer;
}
static int identity_matches(int32_t pid, uint64_t sec, uint64_t usec) {
    TEProcessStats p;
    if (!te_process_identity(pid, &p)) { errno = ESRCH; return 0; }
    if (p.uid != geteuid()) { errno = EPERM; return 0; }
    if (p.startSeconds != sec || p.startMicroseconds != usec) { errno = ESRCH; return 0; }
    return 1;
}
int te_get_background(int32_t pid) {
    struct proc_taskinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info)) != sizeof(info)) return -1;
    /* getpriority(PRIO_DARWIN_PROCESS, other_pid) reports the caller's state
       on current Darwin. A task already at background priority is left alone. */
    return info.pti_priority >= 0 && info.pti_priority <= 4 ? 1 : 0;
}
int te_set_background(int32_t pid, uint64_t sec, uint64_t usec, int enabled) {
    if (!identity_matches(pid, sec, usec)) return -1;
    return setpriority(PRIO_DARWIN_PROCESS, (id_t)pid, enabled ? PRIO_DARWIN_BG : 0);
}
int te_signal_process(int32_t pid, uint64_t sec, uint64_t usec, int number) {
    if (number != SIGSTOP && number != SIGCONT) { errno = EINVAL; return -1; }
    if (!identity_matches(pid, sec, usec)) return -1;
    return kill(pid, number);
}
int te_cpu_ticks(TECPUTicks *out) {
    host_cpu_load_info_data_t data;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t result = host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&data, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (result != KERN_SUCCESS) return 0;
    out->user = data.cpu_ticks[CPU_STATE_USER]; out->system = data.cpu_ticks[CPU_STATE_SYSTEM];
    out->idle = data.cpu_ticks[CPU_STATE_IDLE]; out->nice = data.cpu_ticks[CPU_STATE_NICE];
    return 1;
}
double te_gpu_percent(void) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator) != KERN_SUCCESS) return -1;
    double value = -1;
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFTypeRef object = IORegistryEntryCreateCFProperty(entry, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
        if (object && CFGetTypeID(object) == CFDictionaryGetTypeID()) {
            CFTypeRef number = CFDictionaryGetValue((CFDictionaryRef)object, CFSTR("Device Utilization %"));
            double reading = -1;
            if (number && CFGetTypeID(number) == CFNumberGetTypeID() &&
                CFNumberGetValue((CFNumberRef)number, kCFNumberDoubleType, &reading) && reading >= 0 && reading <= 100) value = reading;
        }
        if (object) CFRelease(object);
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return value;
}
/* 累计一个 GPU 客户端的执行时间（纳秒）；创建者 PID 解析失败或没有记录时返回 0。 */
static int gpu_client_time(io_registry_entry_t entry, TEProcessGPU *out) {
    CFTypeRef creator = IORegistryEntryCreateCFProperty(entry, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0);
    CFTypeRef usage = IORegistryEntryCreateCFProperty(entry, CFSTR("AppUsage"), kCFAllocatorDefault, 0);
    char text[64] = {0};
    int pid = 0;
    uint64_t total = 0;
    if (creator && CFGetTypeID(creator) == CFStringGetTypeID() &&
        CFStringGetCString((CFStringRef)creator, text, sizeof(text), kCFStringEncodingUTF8) &&
        sscanf(text, "pid %d", &pid) == 1 && pid > 0 &&
        usage && CFGetTypeID(usage) == CFArrayGetTypeID()) {
        CFIndex count = CFArrayGetCount((CFArrayRef)usage);
        for (CFIndex index = 0; index < count; index++) {
            CFTypeRef item = CFArrayGetValueAtIndex((CFArrayRef)usage, index);
            if (!item || CFGetTypeID(item) != CFDictionaryGetTypeID()) continue;
            CFTypeRef number = CFDictionaryGetValue((CFDictionaryRef)item, CFSTR("accumulatedGPUTime"));
            int64_t value = 0;
            if (number && CFGetTypeID(number) == CFNumberGetTypeID() &&
                CFNumberGetValue((CFNumberRef)number, kCFNumberSInt64Type, &value) && value > 0) total += (uint64_t)value;
        }
    }
    if (creator) CFRelease(creator);
    if (usage) CFRelease(usage);
    if (total == 0) return 0;
    *out = (TEProcessGPU){ pid, total };
    return 1;
}

/* GPU 用户客户端挂在 AGXAccelerator 下，不能通过服务匹配取得，只遍历加速器的直接子节点。
   同一 PID 可能出现多条，由调用方合并。 */
int te_gpu_process_times(TEProcessGPU *out, int capacity) {
    if (!out || capacity <= 0) return -1;
    io_iterator_t accelerators = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &accelerators) != KERN_SUCCESS) return -1;
    int found = 0;
    io_registry_entry_t accelerator;
    while ((accelerator = IOIteratorNext(accelerators))) {
        io_iterator_t children = 0;
        if (IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS) {
            io_registry_entry_t child;
            while ((child = IOIteratorNext(children))) {
                if (found < capacity && IOObjectConformsTo(child, "IOUserClient") &&
                    gpu_client_time(child, &out[found])) found++;
                IOObjectRelease(child);
            }
            IOObjectRelease(children);
        }
        IOObjectRelease(accelerator);
    }
    IOObjectRelease(accelerators);
    return found;
}
/* 读取 GPU 型号与核心数；只在第一次打开详情时调用。 */
int te_gpu_info(char *model, uint32_t length, int32_t *cores) {
    if (!model || length == 0 || !cores) return 0;
    model[0] = 0; *cores = 0;
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator) != KERN_SUCCESS) return 0;
    io_registry_entry_t entry = IOIteratorNext(iterator);
    int found = 0;
    if (entry) {
        CFTypeRef name = IORegistryEntryCreateCFProperty(entry, CFSTR("model"), kCFAllocatorDefault, 0);
        if (name && CFGetTypeID(name) == CFStringGetTypeID()) {
            found = CFStringGetCString((CFStringRef)name, model, length, kCFStringEncodingUTF8) ? 1 : 0;
        }
        if (name) CFRelease(name);
        CFTypeRef number = IORegistryEntryCreateCFProperty(entry, CFSTR("gpu-core-count"), kCFAllocatorDefault, 0);
        if (number && CFGetTypeID(number) == CFNumberGetTypeID()) {
            CFNumberGetValue((CFNumberRef)number, kCFNumberSInt32Type, cores);
            found = 1;
        }
        if (number) CFRelease(number);
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    return found;
}
static volatile sig_atomic_t worker_exit = 0;
static void on_worker_signal(int number) { (void)number; worker_exit = 1; }
void te_install_worker_signals(void) {
    signal(SIGTERM, on_worker_signal); signal(SIGINT, on_worker_signal);
    signal(SIGHUP, on_worker_signal); signal(SIGPIPE, SIG_IGN);
}
int te_worker_should_exit(void) { return worker_exit; }
