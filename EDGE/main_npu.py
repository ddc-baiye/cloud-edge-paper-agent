import os
import sys
import logging
from logging.handlers import RotatingFileHandler
import time

if sys.stdout is not None:
    sys.stdout.reconfigure(encoding='utf-8')
if sys.stderr is not None:
    sys.stderr.reconfigure(encoding='utf-8')

logger = logging.getLogger('npu_service')
logger.setLevel(logging.INFO)
logger.propagate = False
logger.handlers.clear()
file_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
_log_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'logs')
os.makedirs(_log_dir, exist_ok=True)
try:
    file_handler = RotatingFileHandler(os.path.join(_log_dir, 'npu_service.log'), maxBytes=10*1024*1024, backupCount=3, encoding='utf-8')
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)
except Exception as e:
    if sys.stderr:
        sys.stderr.write(f"CRITICAL: Failed to create log file: {e}\n")
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(file_formatter)
logger.addHandler(console_handler)

logger.info("========================================")
logger.info("NPU 服务正在启动 (Booting NPU Service)...")
logger.info(f"当前工作目录: {os.getcwd()}")
logger.info(f"Python 解释器: {sys.executable}")
logger.info("========================================")

try:
    logger.info("正在导入 Flask...")
    from flask import Flask, request, jsonify, Response, stream_with_context
    from flask_cors import CORS, cross_origin
    import random
    import json
    import re
    import threading
    import urllib.request
    from queue import Queue
    from typing import Dict
    from werkzeug.utils import secure_filename
    import fitz
    import psutil
    import torch
    import numpy as np
    import openvino_genai as ov_genai
    logger.info("所有模块导入成功!")
except ImportError as e:
    logger.critical(f"模块导入失败: {e}")
    sys.exit(1)
except Exception as e:
    logger.critical(f"启动期间发生未知错误: {e}")
    import traceback
    logger.critical(traceback.format_exc())
    sys.exit(1)

def log_info(msg):
    logger.info(msg)

def log_error(msg):
    logger.error(msg)

app = Flask(__name__, template_folder='templates')
CORS(app)
app.config['JSON_AS_ASCII'] = False
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'txt', 'pdf', 'md', 'doc', 'docx'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024
INPUT_TEXT_LIMIT = 2000

pipe = None
pipe_translate = None
NPU_EXPORTER_URL = os.getenv('NPU_EXPORTER_URL', 'http://127.0.0.1:9201/metrics')
_cpu_percent_lock = threading.Lock()
_latest_cpu_percent = psutil.cpu_percent(interval=0.1)

def sample_cpu_usage():
    global _latest_cpu_percent
    while True:
        value = psutil.cpu_percent(interval=0.5)
        with _cpu_percent_lock:
            _latest_cpu_percent = value

def get_latest_cpu_percent() -> float:
    with _cpu_percent_lock:
        return round(_latest_cpu_percent, 1)

threading.Thread(target=sample_cpu_usage, name='cpu-usage-sampler', daemon=True).start()

def build_qwen3_non_thinking_prompt(model_pipe, prompt: str) -> str:
    tokenizer = model_pipe.get_tokenizer()
    messages = [{"role": "user", "content": prompt}]
    return tokenizer.apply_chat_template(messages, add_generation_prompt=True, extra_context={"enable_thinking": False})

def count_tokens(model_pipe, text: str) -> int:
    if not text:
        return 0
    tokenized = model_pipe.get_tokenizer().encode(text, add_special_tokens=False)
    return int(np.asarray(tokenized.attention_mask.data).sum())

def build_usage(model_pipe, input_text: str, output_text: str, total_time: float,
                first_token_latency: float, model_label: str, device: str) -> Dict:
    input_tokens = count_tokens(model_pipe, input_text)
    output_tokens = count_tokens(model_pipe, output_text)
    return {
        'input_tokens': input_tokens,
        'output_tokens': output_tokens,
        'total_tokens': input_tokens + output_tokens,
        'generation_seconds': round(total_time, 3),
        'first_token_seconds': round(first_token_latency, 3),
        'tokens_per_second': round(output_tokens / total_time, 2) if total_time > 0 else 0,
        'model': model_label,
        'device': device,
    }

def encode_sse(event: str, data: Dict) -> bytes:
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    return f"event: {event}\ndata: {payload}\n\n".encode('utf-8')

def initialize_model():
    global pipe, pipe_translate
    root_dir = os.path.dirname(os.path.dirname(__file__))
    if pipe is None:
        model_path = os.path.join(root_dir, "models", "Qwen3-8b-ov-npu")
        log_info(f"正在初始化通用模型... {model_path}")
        npu_cache_dir = os.path.join(root_dir, "models", ".npu_cache")
        try:
            pipe = ov_genai.LLMPipeline(model_path, 'NPU', MAX_PROMPT_LEN=2048, MIN_RESPONSE_LEN=128, CACHE_DIR=npu_cache_dir)
            log_info("通用模型初始化成功!")
        except Exception as e:
            log_error(f"通用模型初始化失败: {e}")
            raise
    if pipe_translate is None:
        translate_model_path = os.path.join(root_dir, "models", "HY-MT1.5-1.8B-int4-ov")
        log_info(f"正在初始化翻译模型... {translate_model_path}")
        try:
            pipe_translate = ov_genai.LLMPipeline(translate_model_path, 'CPU')
            log_info("翻译模型初始化成功!")
        except Exception as e:
            log_error(f"翻译模型初始化失败: {e}")
    return pipe

def post_process_output(output: str, original_prompt: str) -> str:
    try:
        if output.startswith(original_prompt):
            output = output[len(original_prompt):].strip()
        if '<think>' in output and '</think>' in output:
            start_idx = output.find('<think>')
            end_idx = output.find('</think>') + len('</think>')
            output = output[end_idx:].strip() if start_idx < 10 else output[:start_idx] + output[end_idx:]
        elif '</think>' in output:
            output = output.split('</think>')[-1].strip()
        stop_markers = ['<|endoftext|>', '</s>', '<|im_end|>', '<|im_start|>', '_stop', 'Analysis:']
        for marker in stop_markers:
            if marker in output:
                idx = output.find(marker)
                if idx > len(output) * 0.5:
                    output = output[:idx]
        output = output.strip()
        return output if output else "生成内容为空"
    except Exception as e:
        log_error(f"后处理失败: {e}")
        return output.strip()

def _select_pipeline(task_type: str):
    global pipe, pipe_translate
    if pipe is None:
        initialize_model()
    if task_type == 'translate':
        if pipe_translate is None:
            initialize_model()
        return pipe_translate, "HY-MT(translate)", "CPU"
    return pipe, "Qwen3(general)", "NPU"

def _generation_config(max_tokens: int):
    config = ov_genai.GenerationConfig()
    config.max_new_tokens = min(max_tokens, 10000)
    config.temperature = 0.3
    config.top_p = 0.8
    config.top_k = 40
    config.do_sample = True
    config.repetition_penalty = 1.1
    return config

def generate_text(prompt: str, max_tokens: int = 2000, temperature: float = 0.7, task_type: str = 'general'):
    try:
        current_pipe, model_label, device = _select_pipeline(task_type)
        if current_pipe is None:
            raise RuntimeError(f"{model_label} 模型未成功加载")
        config = _generation_config(max_tokens)
        generation_prompt = prompt
        generate_kwargs = {}
        if task_type != 'translate':
            generation_prompt = build_qwen3_non_thinking_prompt(current_pipe, prompt)
            generate_kwargs["apply_chat_template"] = False
        start_time = time.perf_counter()
        result = current_pipe.generate(generation_prompt, config, **generate_kwargs)
        time_cost = time.perf_counter() - start_time
        result = post_process_output(result, generation_prompt)
        usage = build_usage(current_pipe, generation_prompt, result, time_cost, 0.0, model_label, device)
        return result, usage
    except Exception as e:
        log_error(f"文本生成错误: {e}")
        raise RuntimeError(f"文本生成失败: {e}") from e

def generate_text_stream(prompt: str, max_tokens: int = 2000, temperature: float = 0.7, task_type: str = 'general'):
    current_pipe, model_label, device = _select_pipeline(task_type)
    if current_pipe is None:
        raise RuntimeError(f"{model_label} 模型未成功加载")
    config = _generation_config(max_tokens)
    generation_prompt = prompt
    generate_kwargs = {}
    if task_type != 'translate':
        generation_prompt = build_qwen3_non_thinking_prompt(current_pipe, prompt)
        generate_kwargs["apply_chat_template"] = False
    q = Queue()
    state = {'count': 0, 'first_token_time': None, 'start_time': None, 'output_parts': []}

    def streamer(text: str) -> bool:
        if text:
            if state['count'] == 0:
                state['first_token_time'] = time.perf_counter()
            state['count'] += 1
            state['output_parts'].append(text)
            q.put(('chunk', text))
        return False

    def worker():
        try:
            state['start_time'] = time.perf_counter()
            current_pipe.generate(generation_prompt, config, streamer=streamer, **generate_kwargs)
            end_time = time.perf_counter()
            total_time = end_time - state['start_time']
            first_latency = (state['first_token_time'] - state['start_time']) if state['first_token_time'] else 0.0
            if state['count'] == 0:
                fallback = current_pipe.generate(generation_prompt, config, **generate_kwargs)
                fallback = post_process_output(fallback, generation_prompt)
                if fallback:
                    state['output_parts'].append(fallback)
                    q.put(('chunk', fallback))
            usage = build_usage(current_pipe, generation_prompt, ''.join(state['output_parts']), total_time, first_latency, model_label, device)
            q.put(('usage', usage))
        except Exception as e:
            log_error(f"[{model_label}] 流式生成错误: {e}")
            q.put(('error', {'message': str(e)}))
        finally:
            q.put(None)

    threading.Thread(target=worker, daemon=True).start()
    def event_stream():
        while True:
            item = q.get()
            if item is None:
                break
            event, data = item
            yield encode_sse('chunk', {'text': data}) if event == 'chunk' else encode_sse(event, data)
        yield encode_sse('done', {})
    return event_stream()

class PaperProcessor:
    def extract_text_from_file(self, file_path: str) -> str:
        if file_path.endswith('.pdf'):
            return self.extract_text_from_pdf(file_path)
        if file_path.endswith(('.txt', '.md')):
            with open(file_path, 'r', encoding='utf-8') as f:
                return f.read()
        raise ValueError("不支持的文件格式")
    def extract_text_from_pdf(self, pdf_path: str) -> str:
        doc = fitz.open(pdf_path)
        text = ''.join(page.get_text() for page in doc)
        doc.close()
        return text

paper_processor = PaperProcessor()

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_request_data():
    try:
        if request.content_type and 'application/json' in request.content_type:
            return request.get_json() or {}
        return request.form.to_dict()
    except Exception:
        return {}

def get_text_content():
    data = get_request_data()
    text_content = data.get('text_content', '')
    if not text_content and hasattr(request, 'files') and 'file' in request.files:
        file = request.files['file']
        if file.filename != '' and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
            file.save(file_path)
            try:
                text_content = paper_processor.extract_text_from_file(file_path)
            finally:
                if os.path.exists(file_path):
                    os.remove(file_path)
    return text_content, data

def create_json_response(data, status_code=200):
    return app.response_class(response=json.dumps(data, ensure_ascii=False, indent=2), status=status_code, mimetype='application/json; charset=utf-8')

def validate_text_length(text_content, limit):
    if len(text_content) <= limit:
        return None
    return create_json_response({'error': f'文本长度超过限制（{limit} 个字符），请分段处理'}, 400)

def create_stream_response(stream):
    response = Response(stream_with_context(stream), mimetype='text/event-stream', direct_passthrough=True)
    response.headers['Cache-Control'] = 'no-cache, no-transform'
    response.headers['X-Accel-Buffering'] = 'no'
    response.headers['Connection'] = 'keep-alive'
    response.headers['Content-Encoding'] = 'identity'
    return response

def _grammar_prompt(text):
    return f"""你是一个专业的文本语法修正助手。请对下面给出的文本进行语法修正。
要求：仅修正语法错误，不改变原意；严禁输出思考过程、分析或说明；直接输出修正后的文本。
待修正文本：{text}"""

def _polish_prompt(text, polish_type='academic'):
    chinese_chars = len(re.findall(r'[\u4e00-\u9fff]', text))
    total_chars = len(text.replace(' ', '').replace('\n', ''))
    is_chinese = total_chars > 0 and (chinese_chars / total_chars) > 0.3
    if is_chinese:
        style = '学术规范' if polish_type == 'academic' else '正式规范'
        return f"""你是专业写作润色助手。请对以下中文文本进行{style}润色：保持原意、术语准确、逻辑清晰；不要输出思考过程或修改说明；只输出润色后的文本。\n\n原文：{text}"""
    style = 'academic' if polish_type == 'academic' else 'formal'
    return f"""Polish the following English text in a {style} style. Preserve meaning, improve grammar and clarity, add no new facts, and output only the polished text.\n\n{text}"""

def _translate_prompt(text, direction):
    target = '英文' if direction == 'cn_to_en' else '中文'
    return f"""将以下文本翻译为{target}，保持原意和专业术语准确，只输出翻译结果，不要额外解释：\n\n{text}"""

def _translate_direction(text, requested='auto'):
    if requested != 'auto':
        return requested
    chinese_chars = len(re.findall(r'[\u4e00-\u9fff]', text))
    total_chars = len(text.replace(' ', '').replace('\n', ''))
    return 'cn_to_en' if total_chars > 0 and chinese_chars / total_chars > 0.3 else 'en_to_cn'

@app.route('/api/grammar-check', methods=['POST'])
@cross_origin()
def grammar_check_api():
    try:
        text, _ = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        length_error = validate_text_length(text, INPUT_TEXT_LIMIT)
        if length_error:
            return length_error
        new, usage = generate_text(_grammar_prompt(text), max_tokens=len(text) + 1000, temperature=0.1)
        return create_json_response({'raw': text, 'new': new, 'usage': usage})
    except Exception as e:
        return create_json_response({'error': f'语法检查过程中出现错误: {e}'}, 500)

@app.route('/api/polish', methods=['POST'])
@cross_origin()
def polish_api():
    try:
        text, data = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        length_error = validate_text_length(text, INPUT_TEXT_LIMIT)
        if length_error:
            return length_error
        new, usage = generate_text(_polish_prompt(text, data.get('polish_type', 'academic')), max_tokens=len(text) + 1000, temperature=0.3)
        return create_json_response({'raw': text, 'new': new, 'usage': usage})
    except Exception as e:
        return create_json_response({'error': f'规范润色过程中出现错误: {e}'}, 500)

@app.route('/api/translate', methods=['POST'])
@cross_origin()
def translate_api():
    try:
        text, data = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        length_error = validate_text_length(text, INPUT_TEXT_LIMIT)
        if length_error:
            return length_error
        direction = _translate_direction(text, data.get('direction', 'auto'))
        new, usage = generate_text(_translate_prompt(text, direction), max_tokens=len(text) + 200, temperature=0.1, task_type='translate')
        return create_json_response({'raw': text, 'new': new, 'direction': direction, 'usage': usage})
    except Exception as e:
        return create_json_response({'error': f'智能翻译过程中出现错误: {e}'}, 500)

def _stream_task(prompt, max_tokens, temperature, task_type='general'):
    stream = generate_text_stream(prompt, max_tokens=max_tokens, temperature=temperature, task_type=task_type)
    return create_stream_response(stream)

@app.route('/api/grammar-check-stream', methods=['POST'])
@cross_origin()
def grammar_check_stream_api():
    try:
        text, _ = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        length_error = validate_text_length(text, INPUT_TEXT_LIMIT)
        if length_error:
            return length_error
        return _stream_task(_grammar_prompt(text), len(text) + 1000, 0.1)
    except Exception as e:
        return create_json_response({'error': f'语法检查过程中出现错误: {e}'}, 500)

@app.route('/api/polish-stream', methods=['POST'])
@cross_origin()
def polish_stream_api():
    try:
        text, data = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        length_error = validate_text_length(text, INPUT_TEXT_LIMIT)
        if length_error:
            return length_error
        return _stream_task(_polish_prompt(text, data.get('polish_type', 'academic')), len(text) + 1000, 0.3)
    except Exception as e:
        return create_json_response({'error': f'规范润色过程中出现错误: {e}'}, 500)

@app.route('/api/translate-stream', methods=['POST'])
@cross_origin()
def translate_stream_api():
    try:
        text, data = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        length_error = validate_text_length(text, INPUT_TEXT_LIMIT)
        if length_error:
            return length_error
        direction = _translate_direction(text, data.get('direction', 'auto'))
        return _stream_task(_translate_prompt(text, direction), len(text) + 200, 0.1, task_type='translate')
    except Exception as e:
        return create_json_response({'error': f'智能翻译过程中出现错误: {e}'}, 500)

@app.route('/api/extract-text', methods=['POST'])
@cross_origin()
def extract_text_api():
    try:
        text, _ = get_text_content()
        if not text:
            return create_json_response({'error': '请提供文本内容或上传文件'}, 400)
        return create_json_response({'success': True, 'text_content': text, 'length': len(text)})
    except Exception as e:
        return create_json_response({'error': f'文本提取过程中出现错误: {e}'}, 500)

@app.route('/api/health', methods=['GET'])
@cross_origin()
def health_check():
    try:
        model = initialize_model()
        return create_json_response({'status': 'healthy', 'model_loaded': model is not None, 'translation_model_loaded': pipe_translate is not None})
    except Exception as e:
        return create_json_response({'status': 'error', 'model_loaded': False, 'error': str(e)}, 500)

def set_random_seed(seed: int) -> None:
    random.seed(seed)
    os.environ['PYTHONHASHSEED'] = str(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True

@app.route('/')
def index():
    return create_json_response({
        'message': 'PaperAgent edge API',
        'endpoints': {
            'health': '/api/health', 'grammar_check': '/api/grammar-check',
            'polish': '/api/polish', 'translate': '/api/translate', 'extract_text': '/api/extract-text'
        },
        'supported_formats': list(ALLOWED_EXTENSIONS),
        'max_file_size_mb': app.config['MAX_CONTENT_LENGTH'] / (1024*1024)
    })

def parse_prometheus_labels(raw_labels: str) -> Dict[str, str]:
    return {key: value.replace(r'\"', '"').replace(r'\\', '\\') for key, value in re.findall(r'(\w+)="((?:\\.|[^"])*)"', raw_labels or '')}

def read_npu_exporter_stats() -> Dict:
    npu = {'available': False, 'exporter_up': False, 'name': '', 'utilization_percent': 0.0, 'shared_usage_bytes': 0, 'dedicated_usage_bytes': 0, 'committed_bytes': 0, 'shared_capacity_bytes': 0, 'memory_percent': 0.0}
    try:
        with urllib.request.urlopen(NPU_EXPORTER_URL, timeout=0.8) as response:
            metrics_text = response.read().decode('utf-8', errors='replace')
        npu['exporter_up'] = True
        for line in metrics_text.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            match = re.match(r'^(windows_npu_[a-z_]+)(?:\{([^}]*)\})?\s+([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)$', line)
            if not match:
                continue
            metric, raw_labels, raw_value = match.groups()
            labels = parse_prometheus_labels(raw_labels)
            value = float(raw_value)
            if labels.get('name') and not npu['name']:
                npu['name'] = labels['name']
            if metric == 'windows_npu_present':
                npu['available'] = value >= 1
            elif metric == 'windows_npu_utilization_percent':
                npu['utilization_percent'] = round(value, 1)
            elif metric == 'windows_npu_shared_system_memory_bytes':
                npu['shared_capacity_bytes'] = int(value)
            elif metric == 'windows_npu_adapter_memory_bytes':
                memory_type = labels.get('type')
                if memory_type == 'shared_usage': npu['shared_usage_bytes'] = int(value)
                elif memory_type == 'dedicated_usage': npu['dedicated_usage_bytes'] = int(value)
                elif memory_type == 'total_committed': npu['committed_bytes'] = int(value)
        capacity = npu['shared_capacity_bytes']
        usage = npu['shared_usage_bytes'] + npu['dedicated_usage_bytes']
        if capacity > 0:
            npu['memory_percent'] = round(min(usage / capacity * 100, 100), 1)
    except Exception:
        pass
    return npu

@app.route('/api/stats', methods=['GET'])
def get_system_stats():
    try:
        mem = psutil.virtual_memory()
        return jsonify({'cpu_percent': get_latest_cpu_percent(), 'memory_percent': mem.percent, 'memory_used_gb': round(mem.used / (1024 ** 3), 1), 'memory_total_gb': round(mem.total / (1024 ** 3), 1), 'npu': read_npu_exporter_stats()})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    os.makedirs(UPLOAD_FOLDER, exist_ok=True)
    set_random_seed(1999)
    try:
        initialize_model()
        log_info("模型预加载完成!")
    except Exception as e:
        log_error(f"模型预加载失败，将在首次请求时重试: {e}")
    app.run(debug=False, use_reloader=False, host='0.0.0.0', port=5001)
