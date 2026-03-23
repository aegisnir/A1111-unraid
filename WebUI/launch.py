"""
launch.py — Custom wrapper for AUTOMATIC1111's launch.py.

This file replaces the upstream launch.py inside the Docker image. It exists
for one reason: to prevent sensitive CLI arguments (auth credentials and auth
file paths) from being printed in plain text to the container log.

How it works:
  1. Re-exports everything from modules.launch_utils at module level so that
     other A1111 modules that do `import launch; launch.list_extensions()`
     continue to work normally.
  2. Calls prepare_environment() to install/update dependencies (the same
     first step the upstream launch.py performs).
  3. Replaces the default start() function with a version that prints a
     redacted copy of the CLI args, then hands off to webui.webui() or
     webui.api_only() to actually run the server.

If you need to add new sensitive flags in the future, add them to the
`sensitive_flags` set in _redact_cli_args().
"""

import sys
import shlex
from modules.launch_utils import *  # noqa: F403 — upstream modules expect launch.args, launch.list_extensions, etc.
import modules.launch_utils as launch_utils


def _redact_cli_args(argv):
    """Return a copy of *argv* with sensitive flag values replaced by '<redacted>'.

    Handles both space-separated (--flag value) and equals-separated (--flag=value)
    forms. The flag name is always preserved so the user can see which auth
    mechanisms are active; only the secret value is hidden.

    To protect a new flag, add it to the sensitive_flags set below.
    """
    redacted = []
    sensitive_flags = {"--gradio-auth", "--gradio-auth-path", "--api-auth", "--api-auth-path"}
    i = 0

    while i < len(argv):
        arg = argv[i]
        # Check if this arg matches any sensitive flag (exact or --flag=value form).
        matched_flag = next((flag for flag in sensitive_flags if arg == flag or arg.startswith(flag + "=")), None)
        if matched_flag is None:
            # Not sensitive — pass through unchanged.
            redacted.append(arg)
            i += 1
            continue

        if arg == matched_flag:
            # Space-separated form: "--gradio-auth mysecret"
            # Keep the flag name, replace the next token (the value) with <redacted>.
            redacted.extend([arg, "<redacted>"])
            i += 2  # skip over the value token
        else:
            # Equals-separated form: "--gradio-auth=mysecret"
            # Replace everything after the '=' with <redacted>.
            redacted.append(f"{matched_flag}=<redacted>")
            i += 1

    return redacted


def main() -> None:
    # Install/update Python dependencies (torch, repos, etc.) — same as upstream.
    launch_utils.prepare_environment()

    # Replace the default start() with our redacted version so the "Launching
    # Web UI with arguments: ..." log line never leaks credentials.

    def redacted_start():
        mode = "API server" if "--nowebui" in sys.argv else "Web UI"
        # Print the launch line with sensitive values replaced by <redacted>.
        print(f"Launching {mode} with arguments: {shlex.join(_redact_cli_args(sys.argv[1:]))}")
        # Import webui here (not at module level) because it depends on
        # prepare_environment() having already run.
        import webui
        if "--nowebui" in sys.argv:
            webui.api_only()  # headless API mode
        else:
            webui.webui()     # full Gradio web interface

    launch_utils.start = redacted_start
    launch_utils.start()


if __name__ == "__main__":
    main()