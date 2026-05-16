from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    control_plane_url: str
    gemini_api_key: str
    gemini_model: str
    device_name: str
    poll_interval_s: float
    api_key_path: str

    @classmethod
    def from_env(cls) -> "Config":
        gemini_api_key = os.environ.get("GEMINI_API_KEY")
        if not gemini_api_key:
            raise RuntimeError("Missing required env var: GEMINI_API_KEY")

        return cls(
            control_plane_url=os.environ.get("CONTROL_PLANE_URL", "http://localhost:3000"),
            gemini_api_key=gemini_api_key,
            gemini_model=os.environ.get("GEMINI_MODEL", "gemini-2.0-flash"),
            device_name=os.environ.get("DEVICE_NAME", "cloud-runtime-1"),
            poll_interval_s=float(os.environ.get("POLL_INTERVAL_S", "10")),
            api_key_path=os.environ.get("API_KEY_PATH", ".cloud_api_key"),
        )
