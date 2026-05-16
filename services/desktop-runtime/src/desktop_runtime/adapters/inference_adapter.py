from __future__ import annotations

# Model format: .litertlm (LiteRT-LM format)
# Recommended models from https://huggingface.co/litert-community:
#   Desktop: litert-community/gemma-4-E2B-it-litert-lm
#            file: gemma-4-E2B-it.litertlm (~2.6 GB)
#   Desktop: litert-community/gemma-4-E4B-it-litert-lm
#            file: gemma-4-E4B-it.litertlm (~3.7 GB)
# Backend: use "gpu" on Apple Silicon (Metal), "cpu" otherwise

from abc import ABC, abstractmethod
from dataclasses import dataclass
import logging
import os
import sys
from typing import Any, Callable

logger = logging.getLogger(__name__)


@dataclass
class ModelInfo:
    model_id: str
    model_path: str
    backend: str
    loaded_at: str


@dataclass
class ToolSpec:
    """Wraps a Python callable so LiteRT-LM can auto-generate its function schema."""
    name: str
    handler: Callable[..., Any]


class ConversationSession(ABC):
    @abstractmethod
    def send(self, message: str) -> str:
        """Send one message, get one response. Session maintains history."""
        ...


class InferenceAdapter(ABC):
    @abstractmethod
    async def load(self, model_path: str, backend: str = "cpu") -> None: ...

    @abstractmethod
    async def unload(self) -> None: ...

    @abstractmethod
    def get_loaded_model(self) -> ModelInfo | None: ...

    @abstractmethod
    def new_session(self) -> ConversationSession:
        """Creates a fresh session backed by the loaded engine. Call once per Run."""
        ...


class LiteRTConversationSession(ConversationSession):
    def __init__(self, engine: Any) -> None:
        self._conv = engine.create_conversation()

    def send(self, message: str) -> str:
        result = self._conv.send_message({"role": "user", "content": message})
        content = result.get("content") if isinstance(result, dict) else None
        if not content:
            logger.warning("LiteRT-LM response missing content: %r", result)
            return ""
        return content[0].get("text", "")

    def close(self) -> None:
        try:
            self._conv.__exit__(None, None, None)
        except Exception:
            pass


class LiteRTInferenceAdapter(InferenceAdapter):
    """
    Wraps LiteRT-LM Engine + Conversation.

    Engine owns the model weights; a new Conversation is created per Run
    so each task starts with a clean message history. The same Engine can
    be reused across Runs to avoid reloading weights.
    """

    def __init__(self) -> None:
        self._engine: Any = None  # litert_lm.Engine
        self._model_info: ModelInfo | None = None

    async def load(self, model_path: str, backend: str = "cpu") -> None:
        import datetime

        import litert_lm  # type: ignore[import-not-found]

        backend_enum = (
            litert_lm.Backend.GPU
            if backend.lower() == "gpu"
            else litert_lm.Backend.CPU
        )
        logger.info("Loading model %s on %s backend...", model_path, backend)

        # Suppress C/C++ stderr during model load.
        stderr_fd = sys.stderr.fileno()
        saved_stderr = os.dup(stderr_fd)
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, stderr_fd)
        os.close(devnull)
        try:
            self._engine = litert_lm.Engine(
                model_path=model_path,
                backend=backend_enum,
            ).__enter__()
        finally:
            os.dup2(saved_stderr, stderr_fd)
            os.close(saved_stderr)

        logger.info("Model loaded ✓")
        self._model_info = ModelInfo(
            model_id=model_path.split("/")[-1],
            model_path=model_path,
            backend=backend,
            loaded_at=datetime.datetime.now(datetime.UTC).isoformat(),
        )

    async def unload(self) -> None:
        if self._engine is not None:
            try:
                self._engine.__exit__(None, None, None)
            except Exception:
                pass
        self._engine = None
        self._model_info = None

    def get_loaded_model(self) -> ModelInfo | None:
        return self._model_info

    def new_session(self) -> ConversationSession:
        if self._engine is None:
            raise RuntimeError("Model not loaded — call load() first")
        return LiteRTConversationSession(self._engine)
