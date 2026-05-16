import os
import platform
import subprocess
import tempfile


async def take_screenshot() -> str:
    """Capture the current desktop as a PNG. Returns the saved file path."""
    path = os.path.join(tempfile.gettempdir(), "gemma4all_screenshot.png")
    system = platform.system()
    try:
        if system == "Darwin":
            subprocess.run(["screencapture", "-x", path], check=True, timeout=10)
        elif system == "Linux":
            subprocess.run(["scrot", path], check=True, timeout=10)
        else:
            from PIL import ImageGrab
            ImageGrab.grab().save(path)
        return f"Screenshot saved to {path}"
    except FileNotFoundError:
        return "[error] Screenshot tool not found (install scrot on Linux)"
    except Exception as e:
        return f"[error] take_screenshot failed: {e}"
