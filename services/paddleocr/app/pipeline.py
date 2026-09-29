from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from .adapter import normalize_structure_result


class PaddleOcrPipeline:
    def __init__(self) -> None:
        self._pipeline: Any | None = None

    def predict_page(self, image_path: Path, *, page_number: int) -> dict[str, Any]:
        started = time.perf_counter()
        output = self._get_pipeline().predict(str(image_path))
        raw_result = [_result_to_json(result) for result in output]
        processing_ms = int((time.perf_counter() - started) * 1000)
        return normalize_structure_result(
            raw_result,
            page_number=page_number,
            processing_ms=processing_ms,
        )

    def _get_pipeline(self) -> Any:
        if self._pipeline is None:
            from paddleocr import PPStructureV3

            self._pipeline = PPStructureV3()
        return self._pipeline


def _result_to_json(result: Any) -> Any:
    json_value = getattr(result, "json", None)
    if json_value is not None:
        return json_value
    if hasattr(result, "to_dict"):
        return result.to_dict()
    if isinstance(result, dict):
        return result
    return {"text": str(result)}