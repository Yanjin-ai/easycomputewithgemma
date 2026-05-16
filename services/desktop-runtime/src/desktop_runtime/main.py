"""
Required env vars: CONTROL_PLANE_URL, MODEL_PATH
Optional env vars: BACKEND (cpu/gpu), DEVICE_NAME, POLL_INTERVAL_S, API_KEY_PATH, CHECKPOINT_DB_PATH
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import socket
from typing import Any

import httpx

from desktop_runtime.adapters.inference_adapter import LiteRTInferenceAdapter
from desktop_runtime.artifact_uploader import ArtifactUploader
from desktop_runtime.checkpoint_store import SqliteCheckpointStore
from desktop_runtime.client.control_plane_client import ControlPlaneClient
from desktop_runtime.event_reporter import EventReporter
from desktop_runtime.handoff_receiver import HandoffReceiver
from desktop_runtime.heartbeat_service import HeartbeatService
from desktop_runtime.memory_store import MemoryStore
from desktop_runtime.tool_setup import register_default_tools
from desktop_runtime.tool_registry import ToolRegistry
from desktop_runtime.worker import DesktopWorker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def _load_config() -> dict[str, str]:
    required = ["CONTROL_PLANE_URL", "MODEL_PATH"]
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        raise RuntimeError(f"Missing required env vars: {', '.join(missing)}")
    config = {k: os.environ[k] for k in required}
    config["BACKEND"] = os.environ.get("BACKEND", "cpu")
    config["DEVICE_NAME"] = os.environ.get("DEVICE_NAME", socket.gethostname())
    config["POLL_INTERVAL_S"] = os.environ.get("POLL_INTERVAL_S", "10")
    config["API_KEY_PATH"] = os.environ.get("API_KEY_PATH", ".desktop_api_key")
    config["CHECKPOINT_DB_PATH"] = os.environ.get("CHECKPOINT_DB_PATH", "checkpoints.db")
    if memory_file := os.environ.get("MEMORY_FILE"):
        config["MEMORY_FILE"] = memory_file
    return config


async def _run() -> None:
    config = _load_config()

    registration = await _load_or_register(config)
    api_key = registration["api_key"]
    device_id = registration["device"]["device_id"]

    client = ControlPlaneClient(config["CONTROL_PLANE_URL"], api_key)
    reporter = EventReporter(client, device_id)
    registry = ToolRegistry()
    register_default_tools(registry)
    checkpoint_store = SqliteCheckpointStore(config["CHECKPOINT_DB_PATH"])
    inference = LiteRTInferenceAdapter()
    heartbeat = HeartbeatService(client, device_id, registry)
    memory = MemoryStore(memory_file=config.get("MEMORY_FILE"))
    worker = DesktopWorker(
        inference=inference,
        tool_registry=registry,
        checkpoint_store=checkpoint_store,
        reporter=reporter,
        model_path=config["MODEL_PATH"],
        backend=config["BACKEND"],
        heartbeat_service=heartbeat,
        memory_store=memory,
    )
    handoff_receiver = HandoffReceiver(worker, reporter, client)

    await worker.start()
    heartbeat.start()
    handoff_polling_task = asyncio.create_task(handoff_receiver.start_polling())
    logger.info(
        "Desktop runtime ready (device_id=%s, model=%s, backend=%s)",
        device_id,
        config["MODEL_PATH"],
        config["BACKEND"],
    )

    stop_event = asyncio.Event()

    def _on_signal(*_: object) -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _on_signal)

    await stop_event.wait()
    logger.info("Shutting down…")
    handoff_polling_task.cancel()
    try:
        await handoff_polling_task
    except asyncio.CancelledError:
        pass
    await heartbeat.stop()
    await worker.stop()


async def _load_or_register(config: dict[str, str]) -> dict[str, Any]:
    stored = _load_registration(config["API_KEY_PATH"])
    if stored is not None:
        logger.info("Loaded desktop runtime registration from %s", config["API_KEY_PATH"])
        return stored

    base_url = config["CONTROL_PLANE_URL"].rstrip("/")
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{base_url}/v1/devices",
            json={
                "device_name": config["DEVICE_NAME"],
                "runtime_type": "desktop",
                "permission_scope": "private_lan",
            },
            headers={"Content-Type": "application/json"},
            timeout=10.0,
        )
        response.raise_for_status()
        registration = response.json()

    _save_registration(config["API_KEY_PATH"], registration)
    logger.info("Registered desktop runtime device %s", registration["device"]["device_id"])
    return registration


def _load_registration(path: str) -> dict[str, Any] | None:
    if not os.path.exists(path):
        return None

    with open(path, "r", encoding="utf-8") as f:
        api_key = f.read().strip()

    if not api_key:
        return None

    metadata_path = _metadata_path(path)
    if not os.path.exists(metadata_path):
        logger.warning(
            "%s exists but %s is missing device metadata; registering a new device",
            path,
            metadata_path,
        )
        return None

    with open(metadata_path, "r", encoding="utf-8") as f:
        raw_metadata = f.read().strip()

    try:
        metadata = json.loads(raw_metadata)
    except json.JSONDecodeError:
        logger.warning("%s is invalid JSON; registering a new device", metadata_path)
        return None

    if not metadata.get("device", {}).get("device_id"):
        logger.warning("%s is missing device.device_id; registering a new device", metadata_path)
        return None

    return {"api_key": api_key, "device": metadata["device"]}


def _save_registration(path: str, registration: dict[str, Any]) -> None:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(registration["api_key"])
        f.write("\n")
    os.chmod(path, 0o600)

    metadata_path = _metadata_path(path)
    with open(metadata_path, "w", encoding="utf-8") as f:
        json.dump({"device": registration["device"]}, f, indent=2)
        f.write("\n")
    os.chmod(metadata_path, 0o600)


def _metadata_path(path: str) -> str:
    return f"{path}.registration.json"


def main() -> None:
    asyncio.run(_run())


if __name__ == "__main__":
    main()
