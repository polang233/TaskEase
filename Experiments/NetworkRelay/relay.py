"""回环 TCP 中继实验：验证协作代理的阻断与限速，不接管系统网络。"""
from __future__ import annotations
import asyncio
from dataclasses import dataclass
import time


@dataclass(frozen=True)
class RelayRule:
    blocked: bool = False
    upload_bytes_per_second: int | None = None
    download_bytes_per_second: int | None = None

    def __post_init__(self):
        for rate in (self.upload_bytes_per_second, self.download_bytes_per_second):
            if rate is not None and rate <= 0:
                raise ValueError("Bandwidth must be positive")


class Pacer:
    """同一方向所有连接共享额度，最多允许一个 4 KiB 块的初始突发。"""
    def __init__(self, rate):
        self.rate = rate
        self.next_send = 0.0
        self.lock = asyncio.Lock()

    async def wait(self, size):
        if self.rate is None:
            return
        async with self.lock:
            now = time.monotonic()
            wait = max(0, self.next_send - now)
            self.next_send = max(now, self.next_send) + size / self.rate
            if wait:
                await asyncio.sleep(wait)


class LoopbackRelay:
    """只连接预先指定的本机端口；监听不接收客户端指定的目标地址。"""
    def __init__(self, upstream_port, rule):
        if not 1 <= upstream_port <= 65535:
            raise ValueError("Invalid loopback port")
        self.upstream_port = upstream_port
        self.rule = rule
        self.upload = Pacer(rule.upload_bytes_per_second)
        self.download = Pacer(rule.download_bytes_per_second)
        self.server = None
        self.tasks = set()

    async def start(self):
        self.server = await asyncio.start_server(self._accept, "127.0.0.1", 0)
        return self.server.sockets[0].getsockname()[1]

    async def close(self):
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        pending = list(self.tasks)
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)

    async def _pipe(self, reader, writer, pacer):
        while data := await reader.read(4096):
            await pacer.wait(len(data))
            writer.write(data)
            await writer.drain()
        if writer.can_write_eof():
            writer.write_eof()
            await writer.drain()

    async def _accept(self, reader, writer):
        task = asyncio.current_task()
        self.tasks.add(task)
        upstream = None
        transfers = []
        try:
            if self.rule.blocked:
                return
            remote, upstream = await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1", self.upstream_port), 2)
            transfers = [asyncio.create_task(self._pipe(reader, upstream, self.upload)),
                         asyncio.create_task(self._pipe(remote, writer, self.download))]
            await asyncio.gather(*transfers)
        except (OSError, asyncio.TimeoutError):
            pass
        finally:
            for transfer in transfers:
                transfer.cancel()
            await asyncio.gather(*transfers, return_exceptions=True)
            for stream in (upstream, writer):
                if stream:
                    stream.close()
                    try:
                        await stream.wait_closed()
                    except OSError:
                        pass
            self.tasks.discard(task)
