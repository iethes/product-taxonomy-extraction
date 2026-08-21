#!/usr/bin/env python3
"""Pretty-prints an emit_result JSON object (table/signal/timestamp/message + extras) for a
human -- reads one JSON object from stdin. Used by queue_ctl.sh's `show` subcommand and ad hoc
at a terminal: `some_script.sh ... | tail -1 | .venv/bin/python3 script/lib/format_result.py`.
See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md.
"""
import json
import sys

CORE_FIELDS = ("table", "signal", "timestamp", "message")


def format_result(obj):
    lines = [
        f"Table:   {obj.get('table', '?')}",
        f"Signal:  {obj.get('signal', '?')}",
        f"Time:    {obj.get('timestamp', '?')}",
        f"Message: {obj.get('message', '?')}",
    ]
    extra = {k: v for k, v in obj.items() if k not in CORE_FIELDS}
    if extra:
        lines.append("Extra:")
        lines.extend(f"  {k}: {v}" for k, v in extra.items())
    return "\n".join(lines)


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("(empty result)")
        return 1
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"(unparseable result: {e})")
        print(raw)
        return 1
    if "signal" not in obj and "raw_output" in obj:
        print("(no structured result -- raw fallback stored)")
        print(obj["raw_output"])
        return 0
    print(format_result(obj))
    return 0


def _self_test():
    demo = {
        "timestamp": "2026-08-21T00:00:00Z",
        "table": "shopee_th_test",
        "signal": "DONE",
        "message": "ok",
        "iterations": "3",
    }
    out = format_result(demo)
    assert "Table:   shopee_th_test" in out, out
    assert "Signal:  DONE" in out, out
    assert "iterations: 3" in out, out
    print("self-test OK: format_result.py")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        _self_test()
        sys.exit(0)
    sys.exit(main())
