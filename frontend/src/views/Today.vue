<template>
  <div class="min-h-screen bg-slate-50 dark:bg-slate-900 pb-20">
    <div class="max-w-5xl mx-auto px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-xl font-bold dark:text-white">今日情报</h2>
        <div v-if="newsList.length" class="text-sm text-slate-500 dark:text-slate-400">
          已读 {{ readCount }}/{{ newsList.length }}
        </div>
      </div>

      <!-- 今日摘要 -->
      <div v-if="newsList.length" class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-4">
        <div class="flex items-center justify-between mb-2">
          <h3 class="font-semibold dark:text-slate-100">今日重点</h3>
          <button @click="showDigest = !showDigest" class="text-xs text-slate-500 hover:text-slate-700 dark:text-slate-400">
            {{ showDigest ? '收起' : '展开' }}
          </button>
        </div>
        <div v-if="showDigest" class="space-y-2">
          <div v-for="(item, idx) in digestItems" :key="idx" class="flex items-start space-x-2 text-sm">
            <span class="text-blue-600 dark:text-blue-400 font-medium">{{ idx + 1 }}.</span>
            <span class="text-slate-700 dark:text-slate-300">{{ item }}</span>
          </div>
          <div v-if="digestItems.length === 0" class="text-sm text-slate-400">暂无足够新闻生成摘要</div>
        </div>
      </div>

      <!-- 新闻列表 -->
      <div class="space-y-4">
        <div v-for="(news, idx) in displayedNews" :key="news.id"
             class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 transition-all"
             :class="{ 'ring-2 ring-blue-100 dark:ring-blue-900': !news.is_read }">
          <div class="flex items-start justify-between mb-2">
            <div class="flex items-center space-x-2 text-xs text-slate-500 dark:text-slate-400 flex-wrap gap-y-1">
              <span class="bg-slate-100 dark:bg-slate-700 px-2 py-0.5 rounded">{{ news.source_level }}</span>
              <span class="bg-blue-50 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300 px-2 py-0.5 rounded">{{ news.category }}</span>
              <span>{{ formatDate(news.create_date) }}</span>
              <span v-if="!news.is_read" class="w-2 h-2 rounded-full bg-blue-500"></span>
            </div>
            <div class="flex items-center space-x-2">
              <button @click="toggleBookmark('daily_news', news.id)" class="text-lg" :title="isBookmarked('daily_news', news.id) ? '取消收藏' : '收藏'">
                {{ isBookmarked('daily_news', news.id) ? '★' : '☆' }}
              </button>
              <button @click="toggleRead(news)" class="text-xs px-2 py-1 rounded border dark:border-slate-600" :class="news.is_read ? 'bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-300' : 'bg-slate-50 text-slate-600 dark:bg-slate-700 dark:text-slate-300'">
                {{ news.is_read ? '已读' : '未读' }}
              </button>
            </div>
          </div>

          <div @click="expandNews(news)" class="cursor-pointer">
            <p v-if="news.expanded" class="text-sm text-slate-800 dark:text-slate-200 mb-3 leading-relaxed">{{ news.raw_fact }}</p>
            <p v-else class="text-sm text-slate-800 dark:text-slate-200 mb-3 leading-relaxed line-clamp-3">{{ news.raw_fact }}</p>
            <button v-if="news.raw_fact.length > 120" class="text-xs text-blue-600 dark:text-blue-400 hover:underline mb-2">
              {{ news.expanded ? '收起' : '展开全文' }}
            </button>
          </div>

          <div class="flex items-center space-x-3">
            <a v-if="news.original_url" :href="news.original_url" target="_blank" @click="onOpenSource(news)" class="text-sm text-blue-600 dark:text-blue-400 hover:underline">🔗 查看原文</a>
          </div>
        </div>
      </div>

      <!-- 加载更多（当新闻超过5条） -->
      <div v-if="newsList.length > defaultExpandedCount" class="text-center mt-4">
        <button @click="showAll = !showAll" class="text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200 px-4 py-2">
          {{ showAll ? '收起' : `展开全部 ${newsList.length} 条新闻` }}
        </button>
      </div>

      <div v-if="loading" class="text-center text-slate-500 dark:text-slate-400 py-8">加载中…</div>
      <div v-else-if="newsList.length === 0" class="text-center text-slate-400 dark:text-slate-500 py-12">暂无今日新闻</div>

      <!-- 认知拓展候选 -->
      <h3 class="text-lg font-bold mt-8 mb-3 dark:text-white">认知拓展候选</h3>
      <div class="space-y-3">
        <div v-for="c in candidates" :key="c.id" class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="font-semibold dark:text-slate-100 mb-1">{{ c.topic_name }}</div>
          <p class="text-sm text-slate-600 dark:text-slate-400 mb-1"><span class="font-medium">价值：</span>{{ c.reason_value }}</p>
          <p class="text-sm text-slate-600 dark:text-slate-400 mb-3"><span class="font-medium">争议点：</span>{{ c.controversy }}</p>
          <div class="flex space-x-3">
            <button @click="subscribeTopic(c)" class="px-4 py-1.5 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700">同意订阅</button>
            <button @click="skipTopic(c)" class="px-4 py-1.5 border text-slate-600 dark:text-slate-300 dark:border-slate-600 text-sm rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700">跳过</button>
          </div>
        </div>
      </div>
      <div v-if="candidates.length === 0 && !candidatesLoading" class="text-center text-slate-400 dark:text-slate-500 py-8">暂无候选话题</div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import dayjs from 'dayjs'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const newsList = ref([])
const candidates = ref([])
const loading = ref(false)
const candidatesLoading = ref(false)
const readMap = ref({})
const bookmarkMap = ref({})
const showDigest = ref(true)
const showAll = ref(false)
const defaultExpandedCount = 5

function formatDate (d) {
  return d ? dayjs(d).format('MM-DD') : ''
}

const readCount = computed(() => newsList.value.filter(n => n.is_read).length)

const digestItems = computed(() => {
  return newsList.value
    .filter(n => n.raw_fact && n.raw_fact.length > 10)
    .slice(0, 3)
    .map(n => n.raw_fact.slice(0, 80) + (n.raw_fact.length > 80 ? '…' : ''))
})

const displayedNews = computed(() => {
  const list = showAll.value ? newsList.value : newsList.value.slice(0, defaultExpandedCount)
  return list
})

async function loadNews () {
  loading.value = true
  const today = dayjs().format('YYYY-MM-DD')
  const { data, error } = await auth.supabase
    .from('daily_news')
    .select('*')
    .gte('create_date', today)
    .order('create_date', { ascending: false })
  if (error) {
    console.error('loadNews error:', error)
    loading.value = false
    return
  }
  let list = (data || []).map(n => ({ ...n, expanded: false }))

  // owner 使用全局 is_read；trial/member 使用 user_news_read 隔离阅读状态
  if (!auth.isOwner && list.length) {
    const ids = list.map(n => n.id)
    const { data: reads } = await auth.supabase
      .from('user_news_read')
      .select('news_id,is_read')
      .eq('user_id', auth.user.id)
      .in('news_id', ids)
    readMap.value = {}
    for (const r of reads || []) {
      readMap.value[r.news_id] = r.is_read
    }
    list.forEach(n => {
      n.is_read = readMap.value[n.id] ?? false
    })
  }

  // 加载用户书签
  if (list.length) {
    const newsIds = list.map(n => n.id)
    await loadBookmarks('daily_news', newsIds)
  }

  // 默认展开前 3 条
  list.slice(0, 3).forEach(n => { n.expanded = true })

  newsList.value = list
  loading.value = false
}

async function loadBookmarks (resourceType, ids) {
  const { data } = await auth.supabase
    .from('user_bookmark')
    .select('resource_id')
    .eq('user_id', auth.user.id)
    .eq('resource_type', resourceType)
    .in('resource_id', ids)
  for (const b of data || []) {
    bookmarkMap.value[`${resourceType}:${b.resource_id}`] = true
  }
}

function isBookmarked (resourceType, id) {
  return !!bookmarkMap.value[`${resourceType}:${id}`]
}

async function toggleBookmark (resourceType, id) {
  const key = `${resourceType}:${id}`
  const isMarked = bookmarkMap.value[key]
  if (isMarked) {
    await auth.supabase.from('user_bookmark').delete()
      .eq('user_id', auth.user.id)
      .eq('resource_type', resourceType)
      .eq('resource_id', id)
    delete bookmarkMap.value[key]
  } else {
    await auth.supabase.from('user_bookmark').insert({
      user_id: auth.user.id,
      resource_type: resourceType,
      resource_id: id
    })
    bookmarkMap.value[key] = true
  }
}

async function loadCandidates () {
  candidatesLoading.value = true
  const { data, error } = await auth.supabase
    .from('explore_candidate')
    .select('*')
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
    .limit(5)
  if (error) {
    console.error('loadCandidates error:', error)
  } else {
    candidates.value = data || []
  }
  candidatesLoading.value = false
}

function expandNews (news) {
  news.expanded = !news.expanded
}

async function toggleRead (news) {
  const next = !news.is_read
  if (auth.isOwner) {
    const { error } = await auth.supabase
      .from('daily_news')
      .update({ is_read: next })
      .eq('id', news.id)
    if (!error) {
      news.is_read = next
    }
    return
  }

  const { error } = await auth.supabase.from('user_news_read').upsert({
    user_id: auth.user.id,
    news_id: news.id,
    is_read: next,
    read_at: new Date().toISOString()
  })
  if (!error) {
    news.is_read = next
  }
}

async function onOpenSource (news) {
  await auth.logBrowse('daily_news', news.id)
}

async function subscribeTopic (c) {
  const { count } = await auth.supabase
    .from('subscribe_task')
    .select('*', { count: 'exact', head: true })
    .eq('status', 'active')
  if (count >= 3) {
    alert('同时最多 3 个活跃订阅，请先归档或停止其他专题。')
    return
  }

  const { error } = await auth.supabase.from('subscribe_task').insert({
    topic_name: c.topic_name,
    start_day: dayjs().format('YYYY-MM-DD'),
    status: 'active',
    task_type: 'short',
    reference_urls: c.reference_urls || [],
    created_by: auth.user.id
  })

  if (error) {
    console.error('subscribeTopic error:', error)
    alert('订阅失败：' + error.message)
    return
  }

  await auth.supabase.from('explore_candidate').update({ status: 'subscribe' }).eq('id', c.id)
  await loadCandidates()
  alert('已开启 7 天订阅')
}

async function skipTopic (c) {
  await auth.supabase.from('explore_candidate').update({ status: 'skip' }).eq('id', c.id)
  await loadCandidates()
}

onMounted(() => {
  loadNews()
  loadCandidates()
})
</script>

<style scoped>
.line-clamp-3 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
</style>
