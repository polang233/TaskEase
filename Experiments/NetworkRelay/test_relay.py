"""仅使用自建回环服务，验证字节传输、上游阻断与共享速度额度。"""
import asyncio
import time
import unittest
from relay import LoopbackRelay, RelayRule


class RelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.accepted = 0
        self.payload = b"x" * 65536
        self.received = []
        self.relays = []
        self.server = await asyncio.start_server(self.respond, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def respond(self, reader, writer):
        self.accepted += 1
        self.received.append(await reader.read())
        writer.write(self.payload)
        await writer.drain()
        writer.close()
        await writer.wait_closed()

    async def asyncTearDown(self):
        for relay in self.relays:
            await relay.close()
        self.server.close()
        await self.server.wait_closed()

    async def connect(self, rule):
        relay = LoopbackRelay(self.port, rule)
        self.relays.append(relay)
        return await relay.start()

    async def request(self, port, payload=b"request"):
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        try:
            writer.write(payload)
            await writer.drain()
            writer.write_eof()
            return await asyncio.wait_for(reader.read(), 8)
        finally:
            writer.close()
            await writer.wait_closed()

    async def test_allow_transfers_both_directions(self):
        port = await self.connect(RelayRule())
        self.assertEqual(await self.request(port), self.payload)
        self.assertEqual(self.received, [b"request"])

    async def test_block_never_connects_upstream(self):
        port = await self.connect(RelayRule(blocked=True))
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        self.assertEqual(await asyncio.wait_for(reader.read(), 2), b"")
        writer.close()
        await writer.wait_closed()
        self.assertEqual(self.accepted, 0)

    async def test_download_limit(self):
        port = await self.connect(RelayRule(download_bytes_per_second=32768))
        start = time.monotonic()
        self.assertEqual(await self.request(port), self.payload)
        self.assertGreaterEqual(time.monotonic() - start, 1.75)

    async def test_upload_limit(self):
        port = await self.connect(RelayRule(upload_bytes_per_second=32768))
        start = time.monotonic()
        self.assertEqual(await self.request(port, self.payload), self.payload)
        self.assertGreaterEqual(time.monotonic() - start, 1.75)
        self.assertEqual(self.received, [self.payload])

    async def test_connections_share_download_limit(self):
        self.payload = b"x" * 32768
        port = await self.connect(RelayRule(download_bytes_per_second=32768))
        start = time.monotonic()
        results = await asyncio.gather(self.request(port), self.request(port))
        self.assertEqual(results, [self.payload, self.payload])
        self.assertGreaterEqual(time.monotonic() - start, 1.75)


if __name__ == "__main__":
    unittest.main()
