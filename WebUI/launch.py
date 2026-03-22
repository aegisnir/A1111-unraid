import os
import runpy
import sys
from pathlib import Path


def _patch_launch_logging() -> None:
    launch_utils_path = Path(__file__).resolve().parent / "modules" / "launch_utils.py"
    if not launch_utils_path.exists():
        return

    text = launch_utils_path.read_text(encoding="utf-8")
    original = """def start():\n    print(f\"Launching {'API server' if '--nowebui' in sys.argv else 'Web UI'} with arguments: {shlex.join(sys.argv[1:])}\")\n    import webui\n"""
    replacement = """def _redact_cli_args(argv):\n    redacted = []\n    sensitive_flags = {'--gradio-auth', '--api-auth'}\n    i = 0\n\n    while i < len(argv):\n        arg = argv[i]\n        matched_flag = next((flag for flag in sensitive_flags if arg == flag or arg.startswith(flag + '=')), None)\n        if matched_flag is None:\n            redacted.append(arg)\n            i += 1\n            continue\n\n        if arg == matched_flag:\n            redacted.extend([arg, '<redacted>'])\n            i += 2\n        else:\n            redacted.append(f'{matched_flag}=<redacted>')\n            i += 1\n\n    return redacted\n\n\ndef start():\n    print(f\"Launching {'API server' if '--nowebui' in sys.argv else 'Web UI'} with arguments: {shlex.join(_redact_cli_args(sys.argv[1:]))}\")\n    import webui\n"""

    if original not in text and "_redact_cli_args" in text:
        return

    if original not in text:
        raise RuntimeError("Unable to patch launch_utils.py for auth log redaction; upstream start() signature changed.")

    launch_utils_path.write_text(text.replace(original, replacement), encoding="utf-8")


def main() -> None:
    _patch_launch_logging()
    current_file = Path(__file__).resolve()
    current_dir = current_file.parent
    sys.path.insert(0, str(current_dir))
    runpy.run_path(str(current_file.with_name("webui.py")), run_name="__main__")


if __name__ == "__main__":
    main()