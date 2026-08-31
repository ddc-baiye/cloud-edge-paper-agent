"""Optional MinerU PDF parser used only when a runtime token is supplied."""
import io
import logging
import time
import zipfile
from pathlib import Path
from typing import Generator, Optional, Tuple

import requests

MINERU_BASE = 'https://mineru.net/api/v4'


def _headers(token: str) -> dict:
    return {'Content-Type': 'application/json', 'Authorization': f'Bearer {token}'}


def _apply_upload_url(token: str, file_name: str) -> Optional[Tuple[str, str]]:
    response = requests.post(
        f'{MINERU_BASE}/file-urls/batch',
        headers=_headers(token),
        json={'files': [{'name': file_name}], 'model_version': 'vlm'},
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get('code') != 0:
        logging.warning('MinerU upload-url request failed: %s', payload.get('msg', 'unknown error'))
        return None
    data = payload.get('data') or {}
    urls = data.get('file_urls') or []
    if not data.get('batch_id') or not urls:
        return None
    return str(data['batch_id']), str(urls[0])


def _upload_file(path: Path, upload_url: str) -> None:
    with path.open('rb') as handle:
        response = requests.put(upload_url, data=handle, timeout=300)
    response.raise_for_status()


def _batch_status(batch_id: str, token: str) -> dict:
    response = requests.get(
        f'{MINERU_BASE}/extract-results/batch/{batch_id}',
        headers=_headers(token),
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()
    return payload.get('data') or {} if payload.get('code') == 0 else {}


def _download_markdown(zip_url: str) -> Optional[str]:
    response = requests.get(zip_url, timeout=300)
    response.raise_for_status()
    with zipfile.ZipFile(io.BytesIO(response.content), 'r') as archive:
        names = [name for name in archive.namelist() if name.lower().endswith('.md')]
        if not names:
            return None
        return archive.read(names[0]).decode('utf-8', errors='replace')


def parse_pdf_with_mineru_stream(
    pdf_path: Path,
    token: str,
    max_retries: int = 100,
    retry_interval: int = 3,
) -> Generator[Tuple[str, str], None, Optional[str]]:
    """Yield progress and return MinerU Markdown; never logs the token or signed upload URL."""
    try:
        yield '📤 正在申请上传链接...', '准备在线解析...'
        upload = _apply_upload_url(token, pdf_path.name)
        if not upload:
            yield '__FINAL__', '在线解析服务未返回上传链接'
            return None
        batch_id, upload_url = upload

        yield '📤 正在上传文件...', '上传到在线解析服务...'
        _upload_file(pdf_path, upload_url)

        for _ in range(max_retries):
            status = _batch_status(batch_id, token)
            results = status.get('extract_result') or []
            if not results:
                time.sleep(retry_interval)
                continue
            item = results[0]
            state = item.get('state')
            if state == 'done':
                zip_url = item.get('full_zip_url')
                if not zip_url:
                    yield '__FINAL__', '在线解析完成但缺少结果地址'
                    return None
                yield '📖 正在解析文档...', '下载解析结果...'
                markdown = _download_markdown(zip_url)
                if markdown:
                    yield '__SUCCESS__', markdown
                    return markdown
                yield '__FINAL__', '在线解析结果中未找到 Markdown'
                return None
            if state == 'failed':
                yield '__FINAL__', '在线解析任务失败'
                return None
            progress = item.get('extract_progress') or {}
            extracted = progress.get('extracted_pages', 0)
            total = progress.get('total_pages', 0)
            message = f'已解析 {extracted}/{total} 页' if total else f'任务状态：{state or "pending"}'
            yield '📖 正在解析文档...', message
            time.sleep(retry_interval)
        yield '__FINAL__', '在线解析任务超时'
        return None
    except Exception as exc:
        logging.warning('MinerU parsing failed; local parser will be used: %s', type(exc).__name__)
        yield '__FINAL__', '在线解析不可用，将切换到本地解析'
        return None
