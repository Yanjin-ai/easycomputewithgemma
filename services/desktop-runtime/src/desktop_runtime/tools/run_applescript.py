from __future__ import annotations

import subprocess


def run_applescript(script: str) -> str:
    """
    Run an AppleScript on the Mac and return the output.
    Use this to control Calendar, Mail, Finder, Safari, and other native macOS apps.

    Examples:
    - Create a calendar event: tell application "Calendar" to ...
    - Send an email: tell application "Mail" to ...
    - Get current song in Music: tell application "Music" to ...

    The script runs via 'osascript -e'. Returns stdout on success, or an error message.
    Maximum script length: 4000 characters. Timeout: 30 seconds.
    """
    if len(script) > 4000:
        return "Script too long (max 4000 chars)"

    if "do shell script" in script.lower():
        return "Security: use shell_eval tool for shell commands, not AppleScript"

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return f"AppleScript error: {result.stderr.strip()}"
        return result.stdout.strip() or "Done"
    except subprocess.TimeoutExpired:
        return "AppleScript timed out after 30 seconds"
