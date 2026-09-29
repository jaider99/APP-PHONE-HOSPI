from __future__ import annotations

import os
import tempfile
from pathlib import Path

import httpx
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from pydantic import AnyUrl, BaseModel, Field

from .pipeline import PaddleOcrPipeline


class DocumentPageRequest(BaseModel):
    document_id: str = Field(min_length=1, max_length=128)
    page_number: int = Field(gt=0)
    image_url: AnyUrl


app = FastAPI(title="Revtio PaddleOCR Service", version="0.1.0")
pipeline = PaddleOcrPipeline()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/document/page")
async def process_document_page(
    request: DocumentPageRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    _require_service_auth(authorization)

    with tempfile.TemporaryDirectory(prefix="revtio_paddleocr_") as temp_dir:
        image_path = Path(temp_dir) / f"page_{request.page_number}.img"
        await _download_image(str(request.image_url), image_path)

        return pipeline.predict_page(
            image_path,
            page_number=request.page_number,
        )


@app.post("/v1/extract-page")
async def extract_page(
    page_number: int = Form(...),
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None),
) -> dict:
    _require_service_auth(authorization)

    contents = await file.read()

    if not contents:
        raise HTTPException(
            status_code=400,
            detail="empty_file",
        )

    filename = file.filename or f"page_{page_number}.jpg"
    suffix = Path(filename).suffix or ".jpg"

    with tempfile.TemporaryDirectory(prefix="revtio_paddleocr_") as temp_dir:
        image_path = Path(temp_dir) / f"page_{page_number}{suffix}"
        image_path.write_bytes(contents)

        return pipeline.predict_page(
            image_path,
            page_number=page_number,
        )


def _require_service_auth(authorization: str | None) -> None:
    expected_token = os.getenv("PADDLEOCR_SERVICE_TOKEN")

    if not expected_token:
        raise HTTPException(
            status_code=503,
            detail="service_token_not_configured",
        )

    expected_header = f"Bearer {expected_token}"

    if authorization != expected_header:
        raise HTTPException(
            status_code=401,
            detail="unauthorized",
        )



def _require_service_auth(authorization: str | None) -> None:
    expected_token = os.getenv("PADDLEOCR_SERVICE_TOKEN")
    if not expected_token:
        raise HTTPException(status_code=503, detail="service_token_not_configured")
    expected_header = f"Bearer {expected_token}"
    if authorization != expected_header:
        raise HTTPException(status_code=401, detail="unauthorized")


async def _download_image(image_url: str, image_path: Path) -> None:
    timeout_ms = int(os.getenv("PADDLEOCR_IMAGE_DOWNLOAD_TIMEOUT_MS", "15000"))
    timeout = httpx.Timeout(timeout_ms / 1000)
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False) as client:
        response = await client.get(image_url)
    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(status_code=422, detail="image_fetch_failed")
    content_type = response.headers.get("content-type", "")
    if not content_type.startswith("image/"):
        raise HTTPException(status_code=422, detail="image_content_type_required")
    image_path.write_bytes(response.content)