"""Read-only CPU and physical-footprint measurement for a same-user process.

Usage: python3 Scripts/measure-overhead.py PID --seconds 20
100 percent means one CPU core. CPU and wall time share Mach units.
Offsets follow the public rusage_info_v4 ABI in the macOS 27 SDK.
"""
import argparse
import ctypes
import json
import struct
import time

parser = argparse.ArgumentParser()
parser.add_argument('pid', type=int)
parser.add_argument('--seconds', type=float, default=20)
args = parser.parse_args()
if args.pid <= 1 or not 1 <= args.seconds <= 60:
    parser.error('PID must be above 1; duration must be 1..60 seconds')
lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
lib.proc_pid_rusage.restype = ctypes.c_int
lib.mach_absolute_time.restype = ctypes.c_uint64
def read_usage():
    buffer = ctypes.create_string_buffer(1024)
    if lib.proc_pid_rusage(args.pid, 4, buffer) != 0:
        raise OSError(ctypes.get_errno(), 'Process information unavailable')
    return {'cpu': sum(struct.unpack_from('QQ', buffer.raw, 16)),
            'packageIdleWakeups': struct.unpack_from('Q', buffer.raw, 32)[0],
            'interruptWakeups': struct.unpack_from('Q', buffer.raw, 40)[0],
            'physicalBytes': struct.unpack_from('Q', buffer.raw, 72)[0],
            'startTime': struct.unpack_from('Q', buffer.raw, 80)[0]}
before = read_usage()
start = lib.mach_absolute_time()
time.sleep(args.seconds)
after = read_usage()
end = lib.mach_absolute_time()
if before['startTime'] != after['startTime']:
    raise RuntimeError('Process changed during measurement')
print(json.dumps({'pid': args.pid, 'seconds': args.seconds,
                  'cpuPercentOneCore': 100 * (after['cpu']-before['cpu'])/(end-start),
                  'physicalBytes': after['physicalBytes'],
                  'packageIdleWakeupsPerSecond': (after['packageIdleWakeups']-before['packageIdleWakeups'])/args.seconds,
                  'interruptWakeupsPerSecond': (after['interruptWakeups']-before['interruptWakeups'])/args.seconds}, indent=2))
