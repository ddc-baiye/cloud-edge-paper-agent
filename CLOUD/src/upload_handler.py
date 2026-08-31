import json
import re
import shutil
from pathlib import Path
from typing import Any, Dict, Generator, Tuple

import fitz


def get_extra_dirs() -> Tuple[Path, Path]:
    root = Path(__file__).resolve().parent.parent
    return root / 'extra_input' / 'lunwen', root / 'extra_chunks' / 'lunwen'


def _safe_name(value: str) -> str:
    cleaned = re.sub(r'[^A-Za-z0-9\u4e00-\u9fff._-]+', '_', value).strip('_.')
    return cleaned[:100] or 'uploaded_paper'


def process_uploaded_pdf_stream(pdf_path: Path, mineru_token: str, cfg: Dict[str, Any]) -> Generator[Tuple[str, str], None, Tuple[bool, str]]:
    try:
        pdf_path = Path(pdf_path)
        if pdf_path.suffix.lower() != '.pdf':
            yield '__FINAL__', '仅支持 PDF 文件'
            return False, 'PDF only'
        size_mb = pdf_path.stat().st_size / 1024 / 1024
        if size_mb >= 5:
            yield '__FINAL__', f'文件大小超过 5MB（当前 {size_mb:.2f}MB）'
            return False, 'File too large'

        input_dir, chunks_dir = get_extra_dirs()
        input_dir.mkdir(parents=True, exist_ok=True)
        chunks_dir.mkdir(parents=True, exist_ok=True)
        target = input_dir / _safe_name(pdf_path.name)
        shutil.copy2(pdf_path, target)

        yield '📄 正在解析 PDF...', '使用本地 PyMuPDF 提取可复制文本。'
        doc = fitz.open(str(target))
        page_count = len(doc)
        if page_count > 20:
            doc.close()
            target.unlink(missing_ok=True)
            yield '__FINAL__', f'文件页数超过 20 页（当前 {page_count} 页）'
            return False, 'Too many pages'
        pages = []
        for i, page in enumerate(doc):
            yield '📄 正在解析 PDF...', f'正在处理第 {i+1}/{page_count} 页'
            pages.append(page.get_text())
        doc.close()
        text = '\n\n'.join(p.strip() for p in pages if p.strip()).strip()
        if not text:
            yield '__FINAL__', '未提取到可复制文本；扫描版 PDF 请先进行 OCR。'
            return False, 'No extractable text'

        title = pdf_path.stem.replace('_', ' ').strip() or 'Uploaded Paper'
        first_lines = [x.strip() for x in text.splitlines() if x.strip()]
        if first_lines and len(first_lines[0]) < 180:
            title = first_lines[0]
        summary = text[:1400] + ('…' if len(text) > 1400 else '')
        record = {
            'type': 'summary',
            'id': f"upload-{abs(hash((title, len(text))))}",
            'file': target.name,
            'title': title,
            'authors': '',
            'summary': summary,
            'paragraph_summaries': [],
            'original_text': text[:30000],
            'source': 'local_upload'
        }
        out_file = chunks_dir / f'{_safe_name(title)}.jsonl'
        out_file.write_text(json.dumps(record, ensure_ascii=False) + '\n', encoding='utf-8')
        yield '__FINAL__', f'成功处理文档：{title}'
        return True, title
    except Exception as exc:
        yield '__FINAL__', f'处理失败：{exc}'
        return False, str(exc)
