import unittest

from app.adapter import normalize_structure_result


class PaddleOcrAdapterTest(unittest.TestCase):
    def test_normalizes_text_and_table_regions(self) -> None:
        result = normalize_structure_result(
            [
                {
                    "res": {
                        "blocks": [
                            {
                                "block_label": "text",
                                "text": "Invoice No INV-1",
                                "bbox": [0, 0, 10, 10],
                                "score": 0.95,
                            },
                            {
                                "block_label": "table",
                                "html": "<table><tr><td>Campari</td></tr></table>",
                                "cells": [{"text": "Campari"}],
                            },
                        ]
                    }
                }
            ],
            page_number=3,
            processing_ms=820,
        )

        self.assertTrue(result["success"])
        self.assertEqual(result["page_number"], 3)
        self.assertEqual(len(result["blocks"]), 2)
        self.assertEqual(len(result["text_regions"]), 1)
        self.assertEqual(len(result["tables"]), 1)
        self.assertEqual(result["processing_ms"], 820)

    def test_ignores_empty_visual_blocks(self) -> None:
        result = normalize_structure_result(
            [{"block_label": "image", "bbox": [0, 0, 10, 10]}],
            page_number=1,
            processing_ms=10,
        )

        self.assertEqual(result["blocks"], [])
        self.assertEqual(result["tables"], [])
        self.assertEqual(result["text_regions"], [])


if __name__ == "__main__":
    unittest.main()