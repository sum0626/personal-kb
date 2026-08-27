<template>
  <div class="min-h-screen bg-slate-50 dark:bg-slate-900 pb-20">
    <div class="max-w-5xl mx-auto px-4 py-6">
      <h2 class="text-xl font-bold mb-4 dark:text-white">全局搜索</h2>

      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-6">
        <div class="flex gap-3">
          <input v-model="query" @keyup.enter="doSearch" placeholder="输入关键词搜索新闻与知识卡片…" class="flex-1 border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm" />
          <button @click="doSearch" class="bg-primary text-white px-4 py-2 rounded-lg text-sm hover:bg-slate-800">搜索</button>
        </div>
        <p class="text-xs text-slate-500 dark:text-slate-400 mt-2">支持新闻内容、卡片内容、分类、标签匹配</p>
      </div>

      <div v-if="loading" class="text-center text-slate-500 dark:text-slate-400 py-8">搜索中…</div>

      <div v-else-if="results.length" class="space-y-3">
        <div v-for="r in results" :key="r.id + r.resource_type" class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="flex items-center justify-between mb-2">
            <div class="text-xs">
              <span class="px-2 py-0.5 rounded" :class="r.resource_type === 'daily_news' ? 'bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300' : 'bg-green-100 dark:bg-green-900/50 text-green-700 dark:text-green-300'">
                {{ r.resource_type === 'daily_news' ? '每日新闻' : '知识卡片' }}
              </span>
            </div>
            <span class="text-xs text-slate-400 dark:text-slate-500">相关度 {{ (r.score * 100).toFixed(0) }}%</span>
          </div>
          <div class="text-sm text-slate-800 dark:text-slate-200 mb-2 leading-relaxed">{{ r.title }}</div>
          <div class="text-xs text-slate-500 dark:text-slate-400 mb-3 line-clamp-3">{{ r.content }}</div>
          <div class="flex items-center space-x-3">
            <a v-if="r.original_url" :href="r.original_url" target="_blank" class="text-xs text-blue-600 dark:text-blue-400 hover:underline">🔗 查看原文</a>
            <router-link v-if="r.resource_type === 'knowledge_card'" to="/knowledge" class="text-xs text-blue-600 dark:text-blue-400 hover:underline">前往知识库 →</router-link>
          </div>
        </div>
      </div>

      <div v-else-if="hasSearched" class="text-center text-slate-400 dark:text-slate-500 py-12">未找到匹配结果</div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const query = ref('')
const results = ref([])
const loading = ref(false)
const hasSearched = ref(false)

async function doSearch () {
  const q = query.value.trim()
  if (!q) return
  loading.value = true
  hasSearched.value = true
  try {
    const { data, error } = await auth.supabase.rpc('search_resources', {
      p_query: q,
      p_limit: 30
    })
    if (error) {
      console.error('search error:', error)
      results.value = []
    } else {
      results.value = data || []
    }
  } catch (e) {
    console.error('search exception:', e)
    results.value = []
  }
  loading.value = false
}
</script>

<style scoped>
.line-clamp-3 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
</style>
