from __future__ import annotations

from typing import Any


def normalize_structure_result(
    raw_result: Any,
    *,
    page_number: int,
    processing_ms: int,
) -> dict[str, Any]:
    blocks: list[dict[str, Any]] = []
    tables: list[dict[str, Any]] = []
    text_regions: list[dict[str, Any]] = []

    for payload in _iter_payloads(raw_result):
        # 1. High-level document structure
        parsing_res_list = payload.get("parsing_res_list")

        if isinstance(parsing_res_list, list):
            for entry in parsing_res_list:
                if not isinstance(entry, dict):
                    continue

                block = _to_block(entry)

                if block is not None:
                    blocks.append(block)

        # 2. Individual OCR text lines
        overall_ocr_res = payload.get("overall_ocr_res")

        if isinstance(overall_ocr_res, dict):
            text_regions.extend(
                _overall_ocr_to_text_regions(overall_ocr_res)
            )

        # 3. Dedicated table-recognition results
        table_res_list = payload.get("table_res_list")

        if isinstance(table_res_list, list):
            for entry in table_res_list:
                if not isinstance(entry, dict):
                    continue

                table_entry = dict(entry)
                table_entry["type"] = "table"

                table = _to_block(table_entry)

                if table is not None:
                    table["type"] = "table"
                    tables.append(table)

    # Fallback:
    # If PaddleOCR did not provide dedicated table_res_list,
    # recover tables from parsing_res_list blocks.
    if not tables:
        for block in blocks:
            block_type = str(block.get("type") or "").lower()

            if (
                "table" in block_type
                or block.get("html")
                or block.get("cells")
            ):
                tables.append(block)

    # Fallback:
    # If overall_ocr_res produced no individual OCR regions,
    # keep any textual structural blocks.
    if not text_regions:
        for block in blocks:
            if block.get("text"):
                text_regions.append(block)

    return {
        "success": True,
        "page_number": page_number,
        "blocks": blocks,
        "tables": tables,
        "text_regions": text_regions,
        "processing_ms": processing_ms,
    }


def _iter_payloads(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []

    if isinstance(value, list):
        payloads: list[dict[str, Any]] = []

        for item in value:
            payloads.extend(_iter_payloads(item))

        return payloads

    if not isinstance(value, dict):
        return []

    # Keep compatibility if PaddleOCR wraps a result in {"res": {...}}
    if isinstance(value.get("res"), dict):
        return [value["res"]]

    return [value]


def _overall_ocr_to_text_regions(
    overall_ocr_res: dict[str, Any],
) -> list[dict[str, Any]]:
    rec_texts = overall_ocr_res.get("rec_texts")
    rec_scores = overall_ocr_res.get("rec_scores")
    rec_boxes = overall_ocr_res.get("rec_boxes")
    rec_polys = overall_ocr_res.get("rec_polys")

    if not isinstance(rec_texts, list):
        return []

    scores = rec_scores if isinstance(rec_scores, list) else []
    boxes = rec_boxes if isinstance(rec_boxes, list) else []
    polys = rec_polys if isinstance(rec_polys, list) else []

    regions: list[dict[str, Any]] = []

    for index, text in enumerate(rec_texts):
        if not isinstance(text, str) or not text.strip():
            continue

        confidence: float | None = None

        if index < len(scores):
            score = scores[index]

            if isinstance(score, (int, float)):
                confidence = float(score)

        bbox: Any = None

        if index < len(boxes):
            bbox = boxes[index]
        elif index < len(polys):
            bbox = polys[index]

        regions.append(
            {
                "type": "text",
                "text": text.strip(),
                "html": None,
                "bbox": bbox,
                "confidence": confidence,
                "cells": None,
            }
        )

    return regions


def _to_block(entry: dict[str, Any]) -> dict[str, Any] | None:
    block_type = _first_string(
        entry,
        "type",
        "block_type",
        "block_label",
        "label",
        "category",
    ) or "unknown"

    text = _first_string(
        entry,
        "block_content",
        "text",
        "content",
        "rec_text",
        "markdown",
    )

    html = _first_string(
        entry,
        "pred_html",
        "html",
        "table_html",
    )

    # PPStructureV3 sometimes places table HTML inside block_content.
    if (
        "table" in block_type.lower()
        and text
        and text.lstrip().lower().startswith(("<html", "<table"))
    ):
        html = html or text
        text = None

    bbox = _first_value(
        entry,
        "block_bbox",
        "bbox",
        "box",
        "poly",
        "coordinate",
    )

    confidence = _first_number(
        entry,
        "confidence",
        "score",
        "rec_score",
    )

    cells = _first_value(
        entry,
        "cell_box_list",
        "cells",
        "table_cells",
    )

    if not text and not html and not cells:
        return None

    return {
        "type": block_type,
        "text": text,
        "html": html,
        "bbox": bbox,
        "confidence": confidence,
        "cells": cells,
    }


def _first_string(entry: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = entry.get(key)

        if isinstance(value, str) and value.strip():
            return value.strip()

    return None


def _first_number(entry: dict[str, Any], *keys: str) -> float | None:
    for key in keys:
        value = entry.get(key)

        if isinstance(value, (int, float)):
            return float(value)

    return None


def _first_value(entry: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in entry:
            return entry[key]

    return None