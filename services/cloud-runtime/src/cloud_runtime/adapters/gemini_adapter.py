from __future__ import annotations

import asyncio
import inspect
import logging
from typing import Any

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)


def _python_type_to_gemini(annotation: Any) -> types.Type:
    if annotation in (int,):
        return types.Type.INTEGER
    if annotation in (float,):
        return types.Type.NUMBER
    if annotation in (bool,):
        return types.Type.BOOLEAN
    return types.Type.STRING


def build_gemini_tools(tool_specs: list) -> list[types.Tool]:
    """
    Convert a ToolSpec list into Gemini native Tool definitions.
    Parameter schemas are inferred from each handler's signature.
    """
    declarations: list[types.FunctionDeclaration] = []

    for spec in tool_specs:
        sig = inspect.signature(spec.handler)
        properties: dict[str, types.Schema] = {}
        required: list[str] = []

        for param_name, param in sig.parameters.items():
            if param_name == "self":
                continue
            gemini_type = (
                _python_type_to_gemini(param.annotation)
                if param.annotation != inspect.Parameter.empty
                else types.Type.STRING
            )
            properties[param_name] = types.Schema(type=gemini_type)
            if param.default is inspect.Parameter.empty:
                required.append(param_name)

        declarations.append(
            types.FunctionDeclaration(
                name=spec.name,
                description=getattr(spec.handler, "__doc__", None) or spec.name,
                parameters=types.Schema(
                    type=types.Type.OBJECT,
                    properties=properties,
                    required=required or None,
                ),
            )
        )

    # Sentinel tool — model calls this to signal task completion
    declarations.append(
        types.FunctionDeclaration(
            name="task_completed",
            description="Signal that the task is fully complete. Always call this when done.",
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "summary": types.Schema(
                        type=types.Type.STRING,
                        description="One-paragraph description of what was accomplished.",
                    )
                },
                required=["summary"],
            ),
        )
    )

    return [types.Tool(function_declarations=declarations)]


class GeminiSession:
    """
    A single Gemini chat session for one Run.
    Uses the Gemini API's native function-calling protocol instead of the
    FunctionGemma text-based [TOOL_CALL] format.
    """

    def __init__(
        self, client: genai.Client, model: str, tools: list[types.Tool]
    ) -> None:
        config = types.GenerateContentConfig(tools=tools) if tools else None
        self._chat = client.chats.create(model=model, config=config)

    async def send(self, message: str) -> dict[str, Any]:
        """
        Send a text message.
        Returns one of:
          {"type": "function_call", "name": str, "arguments": dict}
          {"type": "text",          "text": str}
        """
        loop = asyncio.get_running_loop()
        response = await loop.run_in_executor(None, self._chat.send_message, message)
        return _parse_response(response)

    async def send_tool_result(self, tool_name: str, result: Any) -> dict[str, Any]:
        """
        Feed a tool execution result back to the model.
        Returns the same structured dict as send().
        """
        loop = asyncio.get_running_loop()
        part = types.Part(
            function_response=types.FunctionResponse(
                name=tool_name,
                response={"result": str(result)},
            )
        )
        response = await loop.run_in_executor(
            None, self._chat.send_message, [part]
        )
        return _parse_response(response)


class GeminiAdapter:
    """Factory for GeminiSession objects."""

    def __init__(self, api_key: str, model: str) -> None:
        self._client = genai.Client(api_key=api_key)
        self._model = model

    def new_session(self, tools: list[types.Tool] | None = None) -> GeminiSession:
        return GeminiSession(self._client, self._model, tools or [])


# ── helpers ───────────────────────────────────────────────────────────────────

def _parse_response(response: Any) -> dict[str, Any]:
    """Extract a function call or text from a Gemini response."""
    try:
        candidates = getattr(response, "candidates", None) or []
        if candidates:
            parts = getattr(candidates[0].content, "parts", None) or []
            for part in parts:
                fc = getattr(part, "function_call", None)
                if fc and getattr(fc, "name", None):
                    return {
                        "type": "function_call",
                        "name": fc.name,
                        "arguments": dict(fc.args) if fc.args else {},
                    }
    except Exception:
        logger.debug("Could not extract function call from response", exc_info=True)

    text = getattr(response, "text", None) or ""
    return {"type": "text", "text": text}
