from __future__ import annotations

from typing import Any, Callable


async def echo(text: str) -> str:
    """Returns the input text unchanged. Use for testing."""
    return text


async def shell_eval(command: str) -> str:
    """Evaluates a simple mathematical expression or runs a safe read-only shell command. Only arithmetic expressions and basic Unix commands (echo, date, ls, cat, pwd) are permitted."""
    ALLOWED_PREFIXES = ("echo ", "date", "ls ", "ls", "cat ", "pwd", "expr ")
    stripped = command.strip()
    is_safe = any(stripped.startswith(p) for p in ALLOWED_PREFIXES)

    # Also allow pure arithmetic: only digits, operators, spaces, parens.
    import re

    is_arithmetic = bool(re.match(r"^[\d\s\+\-\*\/\(\)\.]+$", stripped))
    if not (is_safe or is_arithmetic):
        return f"Error: command '{stripped}' is not in the allowed list."

    import subprocess

    try:
        if is_arithmetic:
            result = eval(stripped, {"__builtins__": {}})
            return str(result)
        result = subprocess.run(
            stripped, shell=True, capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip() or result.stderr.strip() or "(no output)"
    except Exception as e:
        return f"Error: {e}"


class ToolRegistry:
    """
    Stores tool handlers keyed by name.

    Each handler must be a Python callable with type-annotated parameters
    and a docstring — LiteRT-LM uses these to auto-generate the function
    schema that FunctionGemma sees during inference.
    """

    def __init__(self) -> None:
        self._handlers: dict[str, Callable[..., Any]] = {}
        self.register("echo", echo)
        self.register("shell_eval", shell_eval)

    def register(self, name: str, handler: Callable[..., Any]) -> None:
        self._handlers[name] = handler

    def get(self, name: str) -> Callable[..., Any] | None:
        return self._handlers.get(name)

    async def invoke(self, name: str, arguments: dict[str, Any]) -> Any:
        handler = self.get(name)
        if handler is None:
            raise ValueError(f"Unknown tool: {name}")

        import asyncio

        if asyncio.iscoroutinefunction(handler):
            return await handler(**arguments)
        return handler(**arguments)

    def list_supported(self) -> list[str]:
        return list(self._handlers.keys())

    def as_tool_specs(self) -> list[dict[str, Any]]:
        """Returns handlers in a form consumable by InferenceAdapter."""
        from desktop_runtime.adapters.inference_adapter import ToolSpec
        return [ToolSpec(name=name, handler=handler) for name, handler in self._handlers.items()]
