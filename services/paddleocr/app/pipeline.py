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

        print(
            f"[PADDLE_RAW] page={page_number} "
            f"result_count={len(raw_result)}"
        )

        for index, item in enumerate(raw_result):
            if isinstance(item, dict):
                print(
                    f"[PADDLE_RAW] page={page_number} "
                    f"item={index} "
                    f"keys={list(item.keys())}"
                )

                for key, value in item.items():
                    if isinstance(value, dict):
                        print(
                            f"[PADDLE_RAW] page={page_number} "
                            f"item={index} "
                            f"key={key} "
                            f"type=dict "
                            f"keys={list(value.keys())}"
                        )

                    elif isinstance(value, list):
                        print(
                            f"[PADDLE_RAW] page={page_number} "
                            f"item={index} "
                            f"key={key} "
                            f"type=list "
                            f"length={len(value)}"
                        )

                        if value:
                            first_item = value[0]

                            if isinstance(first_item, dict):
                                print(
                                    f"[PADDLE_RAW] page={page_number} "
                                    f"item={index} "
                                    f"key={key} "
                                    f"first_item_keys={list(first_item.keys())}"
                                )
                            else:
                                print(
                                    f"[PADDLE_RAW] page={page_number} "
                                    f"item={index} "
                                    f"key={key} "
                                    f"first_item_type={type(first_item).__name__}"
                                )

                    else:
                        print(
                            f"[PADDLE_RAW] page={page_number} "
                            f"item={index} "
                            f"key={key} "
                            f"type={type(value).__name__}"
                        )

            else:
                print(
                    f"[PADDLE_RAW] page={page_number} "
                    f"item={index} "
                    f"type={type(item).__name__}"
                )

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
        return _unwrap_result_payload(json_value)

    if hasattr(result, "to_dict"):
        return _unwrap_result_payload(result.to_dict())

    if isinstance(result, dict):
        return _unwrap_result_payload(result)

    return {"text": str(result)}


def _unwrap_result_payload(value: Any) -> Any:
    if (
        isinstance(value, dict)
        and isinstance(value.get("res"), dict)
    ):
        return value["res"]

    return value