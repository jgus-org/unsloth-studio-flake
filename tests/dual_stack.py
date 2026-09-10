"""Exercise the real backend entrypoint without loading the GPU application."""

import asyncio
import contextlib
import importlib
import io
from pathlib import Path
import runpy
import socket
import struct
import sys
import unittest


source = Path(sys.argv.pop(1)).resolve()
dual_stack = sys.argv.pop(1) == "dual-stack"
sys.path.insert(0, str(source))
native_setsockopt = socket.socket.setsockopt
calls = []


def recording_setsockopt(sock, level, option, value, *args, **kwargs):
    calls.append((level, option, value, args, kwargs))
    return native_setsockopt(sock, level, option, value, *args, **kwargs)


# The patch must be installed by normal entrypoint loading. Never import or
# invoke its helper directly; --help traverses the production -m entrypoint
# while avoiding model downloads, subprocesses and GPU initialization.
socket.socket.setsockopt = recording_setsockopt
with contextlib.redirect_stdout(io.StringIO()):
    previous_argv = sys.argv
    sys.argv = ["studio.backend.run", "--help"]
    try:
        runpy.run_module("studio.backend.run", run_name="__main__")
    except SystemExit as error:
        if error.code != 0:
            raise
    else:
        raise AssertionError("The backend entrypoint did not handle --help")
    finally:
        sys.argv = previous_argv

entrypoint = importlib.import_module("studio.backend.run")
assert Path(entrypoint.__file__).resolve() == source / "studio/backend/run.py"


class DualStackTests(unittest.TestCase):
    def setUp(self):
        calls.clear()

    def test_entrypoint_and_service_arguments(self):
        self.assertEqual(
            socket.socket.setsockopt is not recording_setsockopt, dual_stack
        )
        arguments = entrypoint._build_arg_parser().parse_args(
            ["--host", "::", "--port", "8000", "--parallel", "2"]
        )
        self.assertEqual((arguments.host, arguments.port, arguments.parallel), ("::", 8000, 2))

    def test_truthy_v6only_is_suppressed_only_in_variant(self):
        with socket.socket(socket.AF_INET6) as listener:
            native_setsockopt(listener, socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            for value in (1, True):
                calls.clear()
                listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, value)
                self.assertEqual(len(calls), 0 if dual_stack else 1)
                self.assertEqual(
                    listener.getsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY),
                    0 if dual_stack else 1,
                )

    def test_false_v6only_is_forwarded(self):
        with socket.socket(socket.AF_INET6) as listener:
            native_setsockopt(listener, socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            self.assertEqual(calls, [(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0, (), {})])
            self.assertEqual(listener.getsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY), 0)

    def test_other_options_and_errors_are_forwarded(self):
        with socket.socket() as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.assertEqual(calls, [(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1, (), {})])
            self.assertEqual(listener.getsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR), 1)
            calls.clear()
            linger = struct.pack("ii", 1, 2)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, linger)
            self.assertEqual(calls, [(socket.SOL_SOCKET, socket.SO_LINGER, linger, (), {})])
            self.assertEqual(listener.getsockopt(socket.SOL_SOCKET, socket.SO_LINGER, len(linger)), linger)
            calls.clear()
            with self.assertRaises(OSError):
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, None, 0)
            self.assertEqual(calls, [(socket.SOL_SOCKET, socket.SO_REUSEADDR, None, (0,), {})])
            calls.clear()
            with self.assertRaises(TypeError):
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1, unexpected=True)
            self.assertEqual(calls, [(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1, (), {"unexpected": True})])
            calls.clear()
            with self.assertRaises(OSError):
                listener.setsockopt(socket.SOL_SOCKET, -1, 1)
            self.assertEqual(calls, [(socket.SOL_SOCKET, -1, 1, (), {})])

    def test_asyncio_wildcard_listener(self):
        async def exercise():
            async def echo(reader, writer):
                try:
                    writer.write(await reader.readexactly(4))
                    await writer.drain()
                finally:
                    writer.close()
                    await writer.wait_closed()

            async with await asyncio.start_server(echo, "::", 0, family=socket.AF_INET6) as server:
                self.assertEqual(len(server.sockets), 1)
                listener = server.sockets[0]
                self.assertEqual(
                    listener.getsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY),
                    0 if dual_stack else 1,
                )
                port = listener.getsockname()[1]

                async def exchange(host):
                    reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), 3)
                    try:
                        writer.write(b"ping")
                        await writer.drain()
                        self.assertEqual(await asyncio.wait_for(reader.readexactly(4), 3), b"ping")
                    finally:
                        writer.close()
                        await writer.wait_closed()

                await exchange("::1")
                if dual_stack:
                    await exchange("127.0.0.1")
                else:
                    with self.assertRaises(OSError):
                        await exchange("127.0.0.1")

        asyncio.run(exercise())


unittest.main()
