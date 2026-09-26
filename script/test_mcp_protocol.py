#!/usr/bin/env python3
"""Smoke-test the embedded MCP helper's stdio protocol without an open app."""

import json
import select
import subprocess
import sys
from pathlib import Path


def main() -> int:
    helper = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "DerivedData/Build/Products/Debug/BuildSweep.app/Contents/Library/HelperTools/BuildSweepMCP"
    )
    if not helper.is_file():
        raise SystemExit(f"MCP helper not found: {helper}; build the BuildSweep scheme first")

    process = subprocess.Popen(
        [str(helper.resolve())],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    def send(message: dict) -> None:
        assert process.stdin is not None
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def receive() -> dict:
        assert process.stdout is not None
        readable, _, _ = select.select([process.stdout], [], [], 5)
        if not readable:
            raise AssertionError("timed out waiting for MCP response")
        line = process.stdout.readline()
        if not line:
            error = process.stderr.read() if process.stderr else ""
            raise AssertionError(f"helper closed stdout early: {error}")
        try:
            return json.loads(line)
        except json.JSONDecodeError as error:
            raise AssertionError(f"stdout included non-JSON protocol output: {line!r}") from error

    try:
        send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {"name": "BuildSweepProtocolTest", "version": "1"},
                },
            }
        )
        initialized = receive()
        assert initialized.get("result", {}).get("serverInfo", {}).get("name") == "BuildSweep"

        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        listed = receive()
        tools = listed.get("result", {}).get("tools", [])
        names = {tool.get("name") for tool in tools}
        expected = {
            "get_status",
            "scan_storage",
            "list_storage_items",
            "inspect_storage_item",
            "prepare_cleanup",
            "get_cleanup_status",
        }
        assert names == expected, f"unexpected MCP tool set: {names}"
        prepare = next(tool for tool in tools if tool["name"] == "prepare_cleanup")
        assert prepare["inputSchema"]["properties"]["itemIDs"]["maxItems"] == 50
        assert "execute_cleanup" not in names and "confirm_cleanup" not in names

        send(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "not_a_buildsweep_tool", "arguments": {}},
            }
        )
        rejected = receive()
        assert rejected.get("result", {}).get("isError") is True
        print("MCP initialize, tool schemas, bounds, unknown-tool rejection, and stdout framing passed")
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
