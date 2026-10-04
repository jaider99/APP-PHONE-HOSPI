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

    for entry in _iter_entries(raw_result):
        block = _to_block(entry)
        if block is None:
            continue
        blocks.append(block)

        block_type = str(block.get("type") or "").lower()
        if "table" in block_type or block.get("cells") or block.get("html"):
            tables.append(block)
        elif block.get("text"):
            text_regions.append(block)

    return {
        "success": True,
        "page_number": page_number,
        "blocks": blocks,
        "tables": tables,
        "text_regions": text_regions,
        "processing_ms": processing_ms,
    }


def _iter_entries(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []
    if isinstance(value, list):
        entries: list[dict[str, Any]] = []
        for item in value:
            entries.extend(_iter_entries(item))
        return entries
    if not isinstance(value, dict):
        return []

    payload = value.get("res") if isinstance(value.get("res"), dict) else value
    for key in ("blocks", "layout", "tables", "text_regions", "parsing_res_list"):
        nested = payload.get(key)
        if isinstance(nested, list):
            return _iter_entries(nested)
    return [payload]


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