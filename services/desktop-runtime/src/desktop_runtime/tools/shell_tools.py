import subprocess


async def run_shell_command(command: str) -> str:
    """Execute a shell command and return its output. Timeout: 60 seconds."""
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        output = result.stdout
        if result.stderr:
            output += f"\n[stderr] {result.stderr}"
        if result.returncode != 0:
            output += f"\n[exit_code: {result.returncode}]"
        return output.strip() or "(no output)"
    except subprocess.TimeoutExpired:
        return "[error] Command timed out after 60 seconds"
    except Exception as e:
        return f"[error] {e}"
