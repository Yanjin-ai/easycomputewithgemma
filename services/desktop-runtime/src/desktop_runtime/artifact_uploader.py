from __future__ import annotations

from desktop_runtime.adapters.types import ArtifactType
from desktop_runtime.client.control_plane_client import ControlPlaneClient
from desktop_runtime.event_reporter import EventReporter


class ArtifactUploader:
    """Phase 1 stub — upload path to control plane TBD in Phase 2."""

    def __init__(self, client: ControlPlaneClient, reporter: EventReporter) -> None:
        self._client = client
        self._reporter = reporter

    async def upload(
        self,
        run_id: str,
        task_id: str,
        content: bytes,
        artifact_type: ArtifactType,
        filename: str,
    ) -> str:
        raise NotImplementedError("ArtifactUploader.upload — storage backend not yet configured")
