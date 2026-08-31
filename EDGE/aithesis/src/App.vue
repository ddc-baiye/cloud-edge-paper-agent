<script setup>
import { ref } from 'vue'
import EdgeView from './components/EdgeView.vue'

const active = ref('edge')
const lang = ref('zh')
</script>

<template>
  <div class="app-shell">
    <header class="topbar">
      <div class="brand">
        <div class="brand-mark">P</div>
        <div>
          <strong>PaperAgent</strong>
          <span>{{ lang === 'zh' ? '云边协同论文智能体' : 'Edge-Cloud Academic Assistant' }}</span>
        </div>
      </div>
      <nav>
        <button :class="{ active: active === 'edge' }" @click="active = 'edge'">
          {{ lang === 'zh' ? '边端写作助手' : 'Edge Writing' }}
        </button>
        <button :class="{ active: active === 'cloud' }" @click="active = 'cloud'">
          {{ lang === 'zh' ? '云端论文检索' : 'Cloud Retrieval' }}
        </button>
      </nav>
      <button class="lang" @click="lang = lang === 'zh' ? 'en' : 'zh'">{{ lang === 'zh' ? 'EN' : '中文' }}</button>
    </header>

    <main>
      <EdgeView v-if="active === 'edge'" :lang="lang" />
      <section v-else class="cloud-frame-wrap">
        <div class="section-heading">
          <div>
            <span class="eyebrow">CLOUD AGENT</span>
            <h1>{{ lang === 'zh' ? '云端论文检索与问答' : 'Cloud Paper Retrieval & QA' }}</h1>
          </div>
          <a href="/cloud/" target="_blank">{{ lang === 'zh' ? '新窗口打开 ↗' : 'Open in new tab ↗' }}</a>
        </div>
        <iframe class="cloud-frame" src="/cloud/" title="PaperAgent Cloud"></iframe>
      </section>
    </main>
  </div>
</template>
