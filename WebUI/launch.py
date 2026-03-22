import runpy
import sys
from pathlib import Path
import shlex


def _redact_cli_args(argv):
    redacted = []
    sensitive_flags = {"--gradio-auth", "--api-auth"}
    i = 0

    while i < len(argv):
        arg = argv[i]
        matched_flag = next((flag for flag in sensitive_flags if arg == flag or arg.startswith(flag + "=")), None)
        if matched_flag is None:
            redacted.append(arg)
            i += 1
            continue

        if arg == matched_flag:
            redacted.extend([arg, "<redacted>"])
            i += 2
        else:
            redacted.append(f"{matched_flag}=<redacted>")
            i += 1

    return redacted


def _patch_launch_logging() -> None:
    modules_dir = Path(__file__).resolve().parent / "modules"
    if not modules_dir.exists():
        return
    import modules.launch_utils as launch_utils

    if getattr(launch_utils, "_a1111_unraid_redaction_patch", False):
        return

    def patched_start():
        mode = "API server" if "--nowebui" in sys.argv else "Web UI"
        print(f"Launching {mode} with arguments: {shlex.join(_redact_cli_args(sys.argv[1:]))}")
        import webui

    launch_utils.start = patched_start
    launch_utils._a1111_unraid_redaction_patch = True


def main() -> None:
    _patch_launch_logging()
    current_file = Path(__file__).resolve()
    current_dir = current_file.parent
    sys.path.insert(0, str(current_dir))
    runpy.run_path(str(current_file.with_name("webui.py")), run_name="__main__")


if __name__ == "__main__":
    main()