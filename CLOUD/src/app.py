import argparse
import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Dict

import gradio as gr
import httpx
import yaml

try:
    from .chat_bot import paper_retrieval_answer_stream
    from .upload_handler import process_uploaded_pdf_stream
except ImportError:
    from chat_bot import paper_retrieval_answer_stream
    from upload_handler import process_uploaded_pdf_stream

ROOT = Path(__file__).resolve().parent.parent
LOG_ROOT = ROOT.parent / 'logs'
LOG_ROOT.mkdir(parents=True, exist_ok=True)
handler = RotatingFileHandler(LOG_ROOT / 'cloud_service.log', maxBytes=10 * 1024 * 1024, backupCount=3, encoding='utf-8')
logging.basicConfig(level=logging.INFO, handlers=[handler, logging.StreamHandler()], format='%(asctime)s %(levelname)s %(message)s')

CSS = """
.gradio-container{max-width:1180px!important;margin:0 auto!important}.hero{padding:18px 22px;border:1px solid #dfe5ee;border-radius:16px;background:linear-gradient(135deg,#f8faff,#eef1ff);margin-bottom:16px}.hero h1{margin:0 0 6px;font-size:28px}.hero p{margin:0;color:#667085}.opea-badge{display:inline-block;margin-top:10px;padding:5px 10px;border-radius:999px;background:#e9f7ef;color:#16794b;font-size:12px;font-weight:700}.compat-badge{display:inline-block;margin-top:10px;padding:5px 10px;border-radius:999px;background:#fff4e5;color:#9a5b00;font-size:12px;font-weight:700}.paperagent-footer{font-size:12px;color:#8a94a6;text-align:center;margin-top:18px}
"""


def read_config(path: str) -> Dict[str, Any]:
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}


def _extract_opea_answer(payload: Any) -> str:
    if isinstance(payload, dict):
        if isinstance(payload.get('answer'), str):
            return payload['answer']
        choices = payload.get('choices') or []
        if choices and isinstance(choices[0], dict):
            first = choices[0]
            if isinstance(first.get('text'), str):
                return first['text']
            message = first.get('message') or {}
            if isinstance(message, dict) and isinstance(message.get('content'), str):
                return message['content']
    if isinstance(payload, str):
        return payload
    return str(payload)


def build_ui(cfg_path: str):
    cfg = read_config(cfg_path)
    opea_gateway = os.getenv('OPEA_GATEWAY_URL', '').strip().rstrip('/')
    opea_timeout = float(os.getenv('OPEA_GATEWAY_TIMEOUT', '600'))

    def ask(question: str, lang: str):
        if not question or not question.strip():
            yield '请输入问题。' if lang == 'zh' else 'Please enter a question.'
            return

        question = question.strip()
        if opea_gateway:
            status = ('🧩 正在通过 OPEA MegaService 执行企业级 RAG 编排...\n\n'
                      if lang == 'zh' else
                      '🧩 Running enterprise RAG orchestration through the OPEA MegaService...\n\n')
            yield status
            try:
                with httpx.Client(timeout=opea_timeout) as client:
                    response = client.post(
                        f'{opea_gateway}/v1/paperagent',
                        json={'text': question, 'temperature': 0.2, 'max_tokens': 1024},
                    )
                    response.raise_for_status()
                    payload = response.json()
                answer = _extract_opea_answer(payload)
                prefix = ('**OPEA Pipeline:** PaperAgent Retriever → OPEA LLM TextGen → MegaService\n\n---\n\n'
                          if lang == 'zh' else
                          '**OPEA Pipeline:** PaperAgent Retriever → OPEA LLM TextGen → MegaService\n\n---\n\n')
                yield prefix + answer
                return
            except Exception as exc:
                logging.exception('OPEA MegaService request failed; falling back to compatibility path')
                warning = (
                    f'⚠️ OPEA MegaService 暂时不可用，已自动回退兼容链路。\n\n`{type(exc).__name__}`\n\n'
                    if lang == 'zh'
                    else f'⚠️ OPEA MegaService is temporarily unavailable; falling back to the compatibility path.\n\n`{type(exc).__name__}`\n\n'
                )
                yield warning

        full = ''
        for chunk in paper_retrieval_answer_stream(cfg, question, 'lunwen', lang=lang):
            full += chunk
            yield full

    def upload(file_path):
        if not file_path:
            return '请选择 PDF 文件。'
        token = str(cfg.get('mineru', {}).get('api_token') or os.getenv('MINERU_API_TOKEN', '')).strip()
        messages = []
        for status, detail in process_uploaded_pdf_stream(Path(file_path), token, cfg):
            messages.append(detail if status == '__FINAL__' else f'{status} {detail}')
        return '\n\n'.join(messages[-5:])

    mode_badge = (
        '<span class="opea-badge">OPEA MegaService Mode</span>'
        if opea_gateway
        else '<span class="compat-badge">Compatibility Mode · set OPEA_GATEWAY_URL to enable OPEA</span>'
    )

    with gr.Blocks(title='PaperAgent Cloud', theme=gr.themes.Soft(), css=CSS) as demo:
        gr.HTML(
            '<div class="hero"><h1>PaperAgent Cloud · OPEA Enterprise RAG</h1>'
            '<p>论文检索、文献问答与 PDF 体验上传。云端支持 OPEA MicroServices + ServiceOrchestrator + MegaService。</p>'
            f'{mode_badge}</div>'
        )
        lang = gr.Radio([('中文', 'zh'), ('English', 'en')], value='zh', label='Language')
        with gr.Row():
            with gr.Column(scale=1):
                question = gr.Textbox(label='检索问题 / Question', lines=6, placeholder='例如：这个系统如何实现云边协同？')
                submit = gr.Button('开始检索 / Ask', variant='primary')
                with gr.Accordion('上传 PDF / Upload PDF', open=False):
                    pdf = gr.File(file_types=['.pdf'], type='filepath', label='PDF (<5MB, <=20 pages)')
                    upload_btn = gr.Button('处理并加入临时论文库')
                    upload_status = gr.Markdown()
            with gr.Column(scale=2):
                answer = gr.Markdown('PaperAgent Cloud is ready.')
        gr.HTML('<div class="paperagent-footer">AI for Good OPEA challenge edition · synthetic demo corpus · runtime uploads are git-ignored</div>')
        submit.click(ask, inputs=[question, lang], outputs=answer)
        question.submit(ask, inputs=[question, lang], outputs=answer)
        upload_btn.click(upload, inputs=pdf, outputs=upload_status)
    demo.queue()
    return demo


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', default=str(ROOT / 'config.yaml'))
    parser.add_argument('--server-name', default='0.0.0.0')
    parser.add_argument('--server-port', type=int, default=7007)
    args = parser.parse_args()
    demo = build_ui(args.config)
    demo.launch(server_name=args.server_name, server_port=args.server_port, strict_cors=False)


if __name__ == '__main__':
    main()
