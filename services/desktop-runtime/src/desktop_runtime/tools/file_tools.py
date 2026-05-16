import os


async def read_file(path: str) -> str:
    """Reads a text file at the given path and returns its contents.

    Only allows reading files under the user's home directory. Expands "~" in
    the path, returns at most the first 4000 characters, and reports errors as
    strings instead of raising exceptions.
    """
    home = os.path.expanduser("~")
    expanded = os.path.expanduser(path)

    if not expanded.startswith(home):
        return "Error: read_file only allows reading files under the user's home directory."

    try:
        with open(expanded, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except FileNotFoundError:
        return f"Error: file not found: {path}"
    except PermissionError:
        return f"Error: permission denied: {path}"
    except Exception as e:
        return f"Error: {e}"

    if len(content) > 4000:
        return content[:4000] + "...(truncated)"
    return content


async def file_read(path: str) -> str:
    """Read and return the text contents of a file at the given path."""
    with open(os.path.expanduser(path), "r", encoding="utf-8", errors="replace") as f:
        return f.read()


async def file_write(path: str, content: str) -> str:
    """Write content to a file at the given path, creating it if needed."""
    expanded = os.path.expanduser(path)
    os.makedirs(os.path.dirname(expanded) or ".", exist_ok=True)
    with open(expanded, "w", encoding="utf-8") as f:
        f.write(content)
    return f"Written {len(content)} chars to {path}"


async def list_directory(path: str = ".") -> str:
    """List files and directories at the given path."""
    expanded = os.path.expanduser(path)
    entries = sorted(os.listdir(expanded))
    lines = []
    for entry in entries:
        full = os.path.join(expanded, entry)
        tag = "[dir]" if os.path.isdir(full) else "[file]"
        lines.append(f"{tag} {entry}")
    return "\n".join(lines) or "(empty directory)"
