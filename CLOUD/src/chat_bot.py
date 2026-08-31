import json
import logging
import re
from pathlib import Path
from typing import Any, Dict, Generator, List

import httpx


def _cloud_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _paper_dirs() -> List[Path]:
    root = _cloud_root()
    return [root / 'chunks' / 'lunwen', root / 'extra_chunks' / 'lunwen']


def load_papers() -> List[Dict[str, Any]]:
    papers: List[Dict[str, Any]] = []
    for directory in _paper_dirs():
        if not directory.exists():
            continue
        for path in sorted(directory.glob('*.jsonl')):
            try:
                for line in path.read_text(encoding='utf-8').splitlines():
                    if not line.strip():
                        continue
                    item = json.loads(line)
                    if item.get('type') == 'summary':
                        papers.append(item)
            except Exception as exc:
                logging.warning('Skipping invalid paper record %s: %s', path, exc)
    return papers


def _tokenize(text: str) -> set[str]:
    return set(re.findall(r'[A-Za-z][A-Za-z0-9_-]{2,}|[\u4e00-\u9fff]{2,}', (text or '').lower()))


def lexical_select(question: str, papers: List[Dict[str, Any]], limit: int = 3) -> List[Dict[str, Any]]:
    q = _tokenize(question)
    scored = []
    for paper in papers:
        haystack = ' '.join([paper.get('title', ''), paper.get('summary', ''), ' '.join(paper.get('paragraph_summaries', []) or [])])
        tokens = _tokenize(haystack)
        score = len(q & tokens)
        if score > 0:
            scored.append((score, paper))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [p for _, p in scored[:limit]]


def _llm_headers(cfg: Dict[str, Any]) -> Dict[str, str]:
    key = str(cfg.get('llm', {}).get('api_key') or '').strip()
    headers = {'Content-Type': 'application/json'}
    if key:
        headers['Authorization'] = f'Bearer {key}'
    return headers


def _normalize_llm_endpoint(value: str) -> str:
    endpoint = str(value or '').strip().rstrip('/')
    if endpoint.lower().endswith('/v1'):
        endpoint = endpoint[:-3].rstrip('/')
    return endpoint


def _chat_completions_url(cfg: Dict[str, Any]) -> str:
    endpoint = _normalize_llm_endpoint(cfg.get('llm', {}).get('base_url') or '')
    if not endpoint:
        raise ValueError('LLM endpoint is empty')
    return f'{endpoint}/v1/chat/completions'


def _llm_enabled(cfg: Dict[str, Any]) -> bool:
    llm = cfg.get('llm', {})
    return bool(
        _normalize_llm_endpoint(llm.get('base_url') or '')
        and str(llm.get('model') or '').strip()
        and str(llm.get('api_key') or '').strip()
    )


def _chat(cfg: Dict[str, Any], messages: List[Dict[str, str]], temperature: float = 0.1) -> str:
    llm = cfg['llm']
    payload = {'model': llm['model'], 'messages': messages, 'temperature': temperature, 'stream': False}
    if str(llm.get('model', '')).lower().startswith('deepseek-v4') and llm.get('disable_thinking', True):
        payload['thinking'] = {'type': 'disabled'}
    timeout = float(llm.get('request_timeout', 3600))
    with httpx.Client(headers=_llm_headers(cfg), timeout=timeout) as client:
        response = client.post(_chat_completions_url(cfg), json=payload)
        response.raise_for_status()
        data = response.json()
    message = data.get('choices', [{}])[0].get('message', {})
    return str(message.get('content') or '').strip()


def _chat_stream(cfg: Dict[str, Any], messages: List[Dict[str, str]], temperature: float = 0.2) -> Generator[str, None, None]:
    llm = cfg['llm']
    payload = {'model': llm['model'], 'messages': messages, 'temperature': temperature, 'stream': True}
    if str(llm.get('model', '')).lower().startswith('deepseek-v4') and llm.get('disable_thinking', True):
        payload['thinking'] = {'type': 'disabled'}
    timeout = float(llm.get('request_timeout', 3600))
    with httpx.Client(headers=_llm_headers(cfg), timeout=timeout) as client:
        with client.stream('POST', _chat_completions_url(cfg), json=payload) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if not line:
                    continue
                raw = line[6:] if line.startswith('data: ') else line
                if raw.strip() == '[DONE]':
                    break
                try:
                    item = json.loads(raw)
                    content = item.get('choices', [{}])[0].get('delta', {}).get('content')
                    if content:
                        yield content
                except Exception:
                    continue


def llm_select(question: str, papers: List[Dict[str, Any]], cfg: Dict[str, Any], limit: int = 3) -> List[Dict[str, Any]]:
    if not _llm_enabled(cfg):
        return lexical_select(question, papers, limit)
    catalog = '\n'.join(f"{i+1}. {p.get('title','')}\n{p.get('summary','')[:700]}" for i, p in enumerate(papers))
    messages = [
        {'role': 'system', 'content': 'Select up to three papers relevant to the question. Return JSON only: {"indices":[1,2]}.'},
        {'role': 'user', 'content': f'Question: {question}\n\nPapers:\n{catalog}'}
    ]
    try:
        content = _chat(cfg, messages, 0.0)
        match = re.search(r'\{.*\}', content, re.S)
        payload = json.loads(match.group(0) if match else content)
        indices = payload.get('indices') or payload.get('selected_indices') or []
        selected = [papers[int(i)-1] for i in indices if str(i).isdigit() and 1 <= int(i) <= len(papers)]
        return selected[:limit]
    except Exception as exc:
        logging.warning('LLM selection failed; using lexical fallback: %s', exc)
        return lexical_select(question, papers, limit)


def _fallback_answer(question: str, selected: List[Dict[str, Any]], lang: str) -> str:
    if not selected:
        return ('未在演示论文库中找到与该问题明显相关的记录。配置云端 LLM API Key 后，可启用模型辅助检索与通用问答。'
                if lang != 'en' else
                'No clearly relevant record was found in the demo library. Configure a cloud LLM API key to enable model-assisted retrieval and general QA.')
    lines = []
    for i, paper in enumerate(selected, 1):
        title = paper.get('title', 'Untitled')
        summary = paper.get('summary', '')
        lines.append(f'{i}. **{title}**\n\n{summary}')
    intro = ('当前未配置完整的云端 LLM endpoint/model/key，以下内容直接基于检索到的论文摘要展示：\n\n' if lang != 'en'
             else 'The cloud LLM endpoint/model/key is not fully configured. The following is shown directly from the retrieved paper summaries:\n\n')
    return intro + '\n\n'.join(lines)


def paper_retrieval_answer_stream(cfg: Dict[str, Any], question: str, standard: str = None, lang: str = 'zh') -> Generator[str, None, None]:
    papers = load_papers()
    yield '🔎 正在读取论文索引...\n\n' if lang != 'en' else '🔎 Loading paper index...\n\n'
    if not papers:
        yield '---\n\n'
        yield '论文库为空。' if lang != 'en' else 'The paper library is empty.'
        return

    selected = llm_select(question, papers, cfg)
    yield ('✅ 检索到的相关论文：\n' if lang != 'en' else '✅ Retrieved papers:\n')
    if selected:
        for paper in selected:
            yield f"- {paper.get('title', 'Untitled')}\n"
    else:
        yield ('- 暂无明显匹配\n' if lang != 'en' else '- No clear match\n')
    yield '\n---\n\n'

    if not _llm_enabled(cfg):
        yield _fallback_answer(question, selected, lang)
        return

    context = '\n\n'.join(
        f"Title: {p.get('title','')}\nAuthors: {p.get('authors','')}\nSummary: {p.get('summary','')}\nText: {str(p.get('original_text',''))[:5000]}"
        for p in selected
    )
    if not context:
        context = 'No directly relevant paper was selected.'
    if lang == 'en':
        system = 'You are an academic literature assistant. Answer from the retrieved paper context. Clearly distinguish evidence from inference and do not fabricate citations.'
        user = f'Question: {question}\n\nRetrieved paper context:\n{context}'
    else:
        system = '你是学术文献问答助手。请仅基于检索到的论文上下文回答，区分论文证据与推断，不得编造论文或引用。'
        user = f'用户问题：{question}\n\n检索到的论文上下文：\n{context}'
    try:
        yield from _chat_stream(cfg, [{'role': 'system', 'content': system}, {'role': 'user', 'content': user}], float(cfg.get('llm', {}).get('temperature', 0.2)))
    except Exception as exc:
        logging.exception('Cloud LLM request failed')
        yield f"\n\n⚠️ Cloud LLM request failed: {exc}"
