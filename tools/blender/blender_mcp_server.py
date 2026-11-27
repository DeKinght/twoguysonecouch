"""Minimalny serwer MCP (stdio) dla dodatku "MCP" z Blender Lab.

Dodatek w Blenderze nasłuchuje na localhost:9876 i wykonuje przysłany kod Pythona.
Ten skrypt to druga połówka: Claude Code uruchamia go jako serwer MCP i dostaje
narzędzie `execute_blender_code`. Bez zewnętrznych bibliotek (sam Python 3).

Rejestracja (raz):
  claude mcp add blender -- python tools/blender/blender_mcp_server.py

Bezpośrednie użycie z konsoli (test / jednorazowy kod):
  python tools/blender/blender_mcp_server.py --run plik.py
"""
import json
import socket
import sys

HOST = "localhost"
PORT = 9876

TOOL = {
    "name": "execute_blender_code",
    "description": (
        "Wykonuje kod Pythona w otwartym Blenderze (dostęp do bpy). Wynik zwracaj przez "
        "przypisanie słownika do zmiennej `result`, np. result = {\"names\": [...]}. "
        "Wydruki (print) też wracają."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {"code": {"type": "string", "description": "Kod Pythona do wykonania w Blenderze."}},
        "required": ["code"],
    },
}


def run_in_blender(code: str, timeout: float = 300.0) -> dict:
    with socket.create_connection((HOST, PORT), timeout=timeout) as s:
        s.sendall((json.dumps({"type": "execute", "code": code, "strict_json": False}) + "\0").encode("utf-8"))
        buf = bytearray()
        while b"\0" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    return json.loads(bytes(buf).split(b"\0", 1)[0].decode("utf-8"))


def _send(msg: dict) -> None:
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def serve() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        req = json.loads(line)
        rid = req.get("id")
        method = req.get("method", "")
        if rid is None:
            continue  # powiadomienia (np. notifications/initialized) - bez odpowiedzi
        if method == "initialize":
            result = {
                "protocolVersion": req.get("params", {}).get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "blender", "version": "1.0"},
            }
        elif method == "tools/list":
            result = {"tools": [TOOL]}
        elif method == "tools/call":
            params = req.get("params", {})
            try:
                resp = run_in_blender(params.get("arguments", {}).get("code", ""))
                text = json.dumps(resp, ensure_ascii=False, indent=1)
                result = {"content": [{"type": "text", "text": text}], "isError": resp.get("status") == "error"}
            except OSError as ex:
                result = {"content": [{"type": "text", "text": "Brak połączenia z Blenderem na %s:%d (%s). "
                                       "Włącz serwer MCP w Blenderze." % (HOST, PORT, ex)}], "isError": True}
        elif method == "ping":
            result = {}
        else:
            _send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "Unknown method " + method}})
            continue
        _send({"jsonrpc": "2.0", "id": rid, "result": result})


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--run":
        print(json.dumps(run_in_blender(open(sys.argv[2], encoding="utf-8").read()), ensure_ascii=False, indent=1))
    else:
        serve()
