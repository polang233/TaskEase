"""Read-only CPU and physical-footprint measurement for a same-user process.

Usage: python3 Scripts/measure-overhead.py PID --seconds 20
100 percent means one CPU core. CPU and wall time share Mach units.
The two uint64 CPU fields follow the UUID in the public rusage_info_v4 ABI.
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
    return sum(struct.unpack_from('QQ', buffer.raw, 16)), struct.unpack_from('Q', buffer.raw, 72)[0]
before, _ = read_usage()
start = lib.mach_absolute_time()
time.sleep(args.seconds)
after, memory = read_usage()
end = lib.mach_absolute_time()
print(json.dumps({'pid': args.pid, 'seconds': args.seconds,
                  'cpuPercentOneCore': 100 * (after-before)/(end-start),
                  'physicalBytes': memory}, indent=2))
