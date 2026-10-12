#include "SystemBridge.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

/* 读取物理内存快照。压缩值为压缩器实际占用，已包含在已用内存内。 */
int te_system_memory(TESystemMemory *out) {
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    vm_size_t page_size = 0;
    kern_return_t status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count);
    kern_return_t page_status = host_page_size(host, &page_size);
    mach_port_deallocate(mach_task_self(), host);
    uint64_t total = 0;
    size_t length = sizeof(total);
    if (status != KERN_SUCCESS || page_status != KERN_SUCCESS || page_size == 0 ||
        sysctlbyname("hw.memsize", &total, &length, NULL, 0) != 0 || total == 0) return 0;
    uint64_t anonymous = vm.internal_page_count;
    anonymous = anonymous > vm.purgeable_count ? anonymous - vm.purgeable_count : 0;
    uint64_t used = (anonymous + vm.wire_count + vm.compressor_page_count) * page_size;
    out->totalBytes = total;
    out->usedBytes = used < total ? used : total;
    out->compressedBytes = (uint64_t)vm.compressor_page_count * page_size;
    struct xsw_usage swap = {0};
    length = sizeof(swap);
    out->swapAvailable = sysctlbyname("vm.swapusage", &swap, &length, NULL, 0) == 0;
    out->swapUsedBytes = out->swapAvailable ? swap.xsu_used : 0;
    return 1;
}

/* 使用 64 位网卡累计字节，只统计活动的 en* 物理接口，避免虚拟接口重复计数。 */
int te_system_network(TESystemNetwork *out, int capacity) {
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (!out || capacity <= 0 || sysctl(mib, 6, NULL, &length, NULL, 0) != 0 ||
        length == 0 || length > 1024 * 1024) return -1;
    char *buffer = malloc(length);
    if (!buffer) return -1;
    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) { free(buffer); return -1; }
    int found = 0;
    const char *end = buffer + length;
    for (const char *cursor = buffer; cursor + 4 <= end;) {
        const struct rt_msghdr *message = (const struct rt_msghdr *)cursor;
        size_t size = message->rtm_msglen;
        if (size < 4 || size > (size_t)(end - cursor)) { found = -1; break; }
        if (message->rtm_type == RTM_IFINFO2 && size >= sizeof(struct if_msghdr2) + sizeof(struct sockaddr_dl)) {
            const struct if_msghdr2 *info = (const struct if_msghdr2 *)cursor;
            const struct sockaddr_dl *address = (const struct sockaddr_dl *)(info + 1);
            size_t name_length = address->sdl_nlen;
            int active = (info->ifm_flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING);
            if (active && !(info->ifm_flags & IFF_LOOPBACK) && name_length >= 3 &&
                name_length <= size - sizeof(*info) - offsetof(struct sockaddr_dl, sdl_data) &&
                address->sdl_data[0] == 'e' && address->sdl_data[1] == 'n' &&
                address->sdl_data[2] >= '0' && address->sdl_data[2] <= '9') {
                if (found >= capacity) { found = -1; break; }
                out[found++] = (TESystemNetwork){ info->ifm_index, info->ifm_data.ifi_ibytes, info->ifm_data.ifi_obytes };
            }
        }
        cursor += size;
    }
    free(buffer);
    return found;
}
