import sys
import shlex
from modules.launch_utils import *  # noqa: F403 — upstream modules expect launch.args, launch.list_extensions, etc.
import modules.launch_utils as launch_utils


def _redact_cli_args(argv):
    redacted = []
    sensitive_flags = {"--gradio-auth", "--gradio-auth-path", "--api-auth", "--api-auth-path"}
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


def main() -> None:
    launch_utils.prepare_environment()

    # Patch start() to redact sensitive CLI arguments from the launch log line.
    _original_start = launch_utils.start

    def redacted_start():
        mode = "API server" if "--nowebui" in sys.argv else "Web UI"
        print(f"Launching {mode} with arguments: {shlex.join(_redact_cli_args(sys.argv[1:]))}")
        import webui
        if "--nowebui" in sys.argv:
            webui.api_only()
        else:
            webui.webui()

    launch_utils.start = redacted_start
    launch_utils.start()


if __name__ == "__main__":
    main()