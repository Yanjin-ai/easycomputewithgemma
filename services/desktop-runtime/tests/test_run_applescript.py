from __future__ import annotations

import subprocess
from unittest.mock import MagicMock, patch

import pytest

from desktop_runtime.tools.run_applescript import run_applescript


def test_basic_applescript():
    mock_result = MagicMock()
    mock_result.returncode = 0
    mock_result.stdout = "hello"
    mock_result.stderr = ""

    with patch("subprocess.run", return_value=mock_result) as mock_run:
        output = run_applescript('return "hello"')

    mock_run.assert_called_once_with(
        ["osascript", "-e", 'return "hello"'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert "hello" in output


def test_timeout_handling():
    with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="osascript", timeout=30)):
        output = run_applescript("delay 60")

    assert output == "AppleScript timed out after 30 seconds"


def test_security_block():
    output = run_applescript('do shell script "rm -rf /"')
    assert output == "Security: use shell_eval tool for shell commands, not AppleScript"


def test_security_block_case_insensitive():
    output = run_applescript('DO SHELL SCRIPT "whoami"')
    assert output == "Security: use shell_eval tool for shell commands, not AppleScript"


def test_applescript_error():
    mock_result = MagicMock()
    mock_result.returncode = 1
    mock_result.stdout = ""
    mock_result.stderr = "execution error: Application not found. (-1728)"

    with patch("subprocess.run", return_value=mock_result):
        output = run_applescript('tell application "NonExistent" to activate')

    assert output.startswith("AppleScript error:")
    assert "execution error" in output


def test_script_too_long():
    long_script = "x" * 4001
    output = run_applescript(long_script)
    assert output == "Script too long (max 4000 chars)"


def test_empty_stdout_returns_done():
    mock_result = MagicMock()
    mock_result.returncode = 0
    mock_result.stdout = ""
    mock_result.stderr = ""

    with patch("subprocess.run", return_value=mock_result):
        output = run_applescript('tell application "Finder" to activate')

    assert output == "Done"
