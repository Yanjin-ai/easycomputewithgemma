from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from typing import Any, Callable

import httpx
from bs4 import BeautifulSoup


@dataclass(frozen=True)
class ToolSpec:
    name: str
    handler: Callable[..., Any]


class ToolRegistry:
    """Stores cloud runtime tool handlers keyed by name."""

    def __init__(self) -> None:
        self._handlers: dict[str, Callable[..., Any]] = {}

    def register(self, name: str, handler: Callable[..., Any]) -> None:
        self._handlers[name] = handler

    def get(self, name: str) -> Callable[..., Any] | None:
        return self._handlers.get(name)

    def list_supported(self) -> list[str]:
        return list(self._handlers.keys())

    def as_tool_specs(self) -> list[ToolSpec]:
        return [ToolSpec(name=name, handler=handler) for name, handler in self._handlers.items()]


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
    except Exception as exc:
        return f"[error] {exc}"


async def web_search(query: str) -> str:
    """Search the web using DuckDuckGo and return top 5 results as text."""
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=15.0) as client:
            response = await client.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query},
                headers={"User-Agent": "Mozilla/5.0"},
            )
        soup = BeautifulSoup(response.text, "html.parser")
        results = []
        for item in soup.select(".result__body")[:5]:
            title = item.select_one(".result__title")
            snippet = item.select_one(".result__snippet")
            if title and snippet:
                results.append(f"- {title.get_text(strip=True)}: {snippet.get_text(strip=True)}")
        return "\n".join(results) if results else "No results found"
    except Exception as exc:
        return f"[error] web_search failed: {exc}"


def register_default_tools(registry: ToolRegistry) -> None:
    """Register all built-in cloud runtime tools."""
    registry.register("file_read", file_read)
    registry.register("file_write", file_write)
    registry.register("list_directory", list_directory)
    registry.register("run_shell_command", run_shell_command)
    registry.register("web_search", web_search)
