<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'

const props = defineProps({ lang: { type: String, default: 'zh' } })
const API_BASE = '/edge-api'
const mode = ref('polish')
const text = ref('The proposed method achieve better performance while keep a low computational cost.')
const output = ref('')
const loading = ref(false)
const error = ref('')
const usage = ref(null)
const stats = ref(null)
let timer = null

const copy = computed(() => props.lang === 'zh' ? {
  title: '本地隐私写作助手', sub: '敏感文本在本机处理，Qwen3 运行于 Intel NPU，HY-MT 翻译运行于 CPU。',
  input: '输入论文文本', output: '处理结果', run: '开始处理', working: '本地模型处理中…',
  grammar: '语法检查', polish: '学术润色', translate: '智能翻译', empty: '请输入需要处理的文本。',
  model: '模型', device: '设备', speed: '生成速度', npu: 'NPU 利用率'
} : {
  title: 'Private Edge Writing Assistant', sub: 'Sensitive text stays local. Qwen3 runs on Intel NPU; HY-MT translation runs on CPU.',
  input: 'Academic text', output: 'Result', run: 'Run', working: 'Local inference…',
  grammar: 'Grammar', polish: 'Academic Polish', translate: 'Translate', empty: 'Enter text to process.',
  model: 'Model', device: 'Device', speed: 'Generation speed', npu: 'NPU utilization'
})

const endpoint = computed(() => ({ grammar: 'grammar-check-stream', polish: 'polish-stream', translate: 'translate-stream' }[mode.value]))

function parseSSE(buffer, onEvent) {
  const blocks = buffer.split('\n\n')
  const rest = blocks.pop() || ''
  for (const block of blocks) {
    let event = 'message'
    let data = ''
    for (const line of block.split('\n')) {
      if (line.startsWith('event:')) event = line.slice(6).trim()
      if (line.startsWith('data:')) data += line.slice(5).trim()
    }
    if (data) {
      try { onEvent(event, JSON.parse(data)) } catch { /* ignore malformed partial events */ }
    }
  }
  return rest
}

async function run() {
  if (!text.value.trim()) { error.value = copy.value.empty; return }
  loading.value = true; error.value = ''; output.value = ''; usage.value = null
  try {
    const body = { text_content: text.value }
    if (mode.value === 'polish') body.polish_type = 'academic'
    if (mode.value === 'translate') body.direction = 'auto'
    const response = await fetch(`${API_BASE}/api/${endpoint.value}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
    })
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}))
      throw new Error(detail.error || `HTTP ${response.status}`)
    }
    const reader = response.body.getReader(); const decoder = new TextDecoder(); let buffer = ''
    while (true) {
      const { value, done } = await reader.read(); if (done) break
      buffer += decoder.decode(value, { stream: true })
      buffer = parseSSE(buffer, (event, data) => {
        if (event === 'chunk') output.value += data.text || ''
        if (event === 'usage') usage.value = data
        if (event === 'error') throw new Error(data.message || 'Inference failed')
      })
    }
  } catch (e) { error.value = e.message || String(e) }
  finally { loading.value = false }
}

async function refreshStats() {
  try { const r = await fetch(`${API_BASE}/api/stats`); if (r.ok) stats.value = await r.json() } catch { /* optional */ }
}

onMounted(() => { refreshStats(); timer = setInterval(refreshStats, 2500) })
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <section class="edge-view">
    <div class="hero-grid">
      <div>
        <span class="eyebrow">EDGE AI · OPENVINO</span>
        <h1>{{ copy.title }}</h1>
        <p>{{ copy.sub }}</p>
      </div>
      <div class="runtime-card">
        <div><span>Qwen3 8B INT4</span><b>Intel NPU</b></div>
        <div><span>HY-MT1.5 1.8B INT4</span><b>CPU</b></div>
        <div v-if="stats?.npu"><span>{{ copy.npu }}</span><b>{{ stats.npu.utilization_percent || 0 }}%</b></div>
      </div>
    </div>

    <div class="mode-tabs">
      <button v-for="item in [['grammar', copy.grammar], ['polish', copy.polish], ['translate', copy.translate]]" :key="item[0]" :class="{ active: mode === item[0] }" @click="mode = item[0]">{{ item[1] }}</button>
    </div>

    <div class="workspace-grid">
      <article class="editor-card">
        <label>{{ copy.input }} <span>{{ text.length }}/2000</span></label>
        <textarea v-model="text" maxlength="2000" spellcheck="false"></textarea>
        <button class="primary" :disabled="loading" @click="run">{{ loading ? copy.working : copy.run }}</button>
        <p v-if="error" class="error">{{ error }}</p>
      </article>
      <article class="editor-card result-card">
        <label>{{ copy.output }}</label>
        <div class="result" :class="{ muted: !output }">{{ output || (loading ? copy.working : '—') }}</div>
        <div v-if="usage" class="usage-row">
          <span>{{ copy.model }}: {{ usage.model }}</span>
          <span>{{ copy.device }}: {{ usage.device }}</span>
          <span>{{ copy.speed }}: {{ usage.tokens_per_second }} tok/s</span>
        </div>
      </article>
    </div>
  </section>
</template>
