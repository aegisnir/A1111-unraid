import sys
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


def main() -> None:
    from modules import launch_utils

    # Run the standard A1111 environment preparation (installs missing pip deps).
    launch_utils.prepare_environment()

    # Patch start() to redact sensitive CLI arguments from the launch log line.
    def redacted_start():
        mode = "API server" if "--nowebui" in sys.argv else "Web UI"
        print(f"Launching {mode} with arguments: {shlex.join(_redact_cli_args(sys.argv[1:]))}")
        import webui

    launch_utils.start = redacted_start
    launch_utils.start()


if __name__ == "__main__":
    main()