from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
from typing import Any

from cloud_runtime.adapters.gemini_adapter import GeminiAdapter
from cloud_runtime.client.control_plane_client import ControlPlaneClient
from cloud_runtime.config import Config
from cloud_runtime.handoff_receiver import HandoffReceiver
from cloud_runtime.heartbeat_service import HeartbeatService
from cloud_runtime.tool_registry import ToolRegistry, register_default_tools
from cloud_runtime.worker import CheckpointManager, CloudWorker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


async def _run() -> None:
    config = Config.from_env()

    registration = await _load_or_register(config)
    api_key = registration["api_key"]
    device_id = registration["device"]["device_id"]

    client = ControlPlaneClient(config.control_plane_url, api_key)
    registry = ToolRegistry()
    register_default_tools(registry)
    inference = GeminiAdapter(api_key=config.gemini_api_key, model=config.gemini_model)
    checkpoint_mgr = CheckpointManager()
    heartbeat = HeartbeatService(client, device_id, registry)
    worker = CloudWorker(
        inference=inference,
        tool_registry=registry,
        checkpoint_manager=checkpoint_mgr,
        client=client,
        heartbeat_service=heartbeat,
    )
    handoff_receiver = HandoffReceiver(worker, client, config.poll_interval_s)

    await worker.start()
    heartbeat.start()
    handoff_polling_task = asyncio.create_task(handoff_receiver.start_polling())
    logger.info("Cloud runtime ready (device_id=%s, model=%s)", device_id, config.gemini_model)

    stop_event = asyncio.Event()

    def _on_signal(*_: object) -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _on_signal)

    await stop_event.wait()
    logger.info("Shutting down...")
    handoff_polling_task.cancel()
    try:
        await handoff_polling_task
    except asyncio.CancelledError:
        pass
    await handoff_receiver.stop()
    await heartbeat.stop()
    await worker.stop()


async def _load_or_register(config: Config) -> dict[str, Any]:
    stored = _load_registration(config.api_key_path)
    if stored is not None:
        logger.info("Loaded cloud runtime registration from %s", config.api_key_path)
        return stored

    client = ControlPlaneClient(config.control_plane_url)
    registration = await client.register_device(config.device_name)
    _save_registration(config.api_key_path, registration)
    logger.info("Registered cloud runtime device %s", registration["device"]["device_id"])
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
