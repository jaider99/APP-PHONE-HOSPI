# Revtio PaddleOCR Service

Server-side PaddleOCR fallback service for Multipage Document Extraction V2.

This service is intentionally separate from Flutter and Supabase Edge Functions. It should run as an authenticated internal container and receive only the minimum page reference needed for OCR fallback.

## Pipeline

- Primary service pipeline: PP-StructureV3.
- OCR/text recognition baseline: PP-OCRv6 as provided by PaddleOCR 3.7.
- Initial deployment target: CPU-capable container with persistent model cache.
- GPU is a benchmark-driven later decision.

## Endpoints

- `GET /health`
- `POST /v1/document/page`

`POST /v1/document/page` requires:

```http
Authorization: Bearer <PADDLEOCR_SERVICE_TOKEN>
```

Request:

```json
{
  "document_id": "uuid",
  "page_number": 3,
  "image_url": "https://signed-url"
}
```

Response:

```json
{
  "success": true,
  "page_number": 3,
  "blocks": [],
  "tables": [],
  "text_regions": [],
  "processing_ms": 820
}
```

Do not send Supabase user JWTs, service-role tokens, OpenRouter keys, or unrelated company data to this service.

## Local Smoke Test

```powershell
python -m unittest discover services/paddleocr/tests
```

Full service tests require installing `requirements.txt`.