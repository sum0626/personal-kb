<template>
  <div class="min-h-screen bg-slate-50 dark:bg-slate-900 pb-20">
    <div class="max-w-5xl mx-auto px-4 py-6">
      <h2 class="text-xl font-bold mb-4 dark:text-white">知识库</h2>

      <!-- 筛选与搜索 -->
      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-4 space-y-3">
        <div class="flex flex-col sm:flex-row sm:items-center gap-3">
          <select v-model="selectedCategory" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm">
            <option value="">全部分类</option>
            <option v-for="cat in categories" :key="cat" :value="cat">{{ cat }}</option>
          </select>
          <input v-model="tagQuery" placeholder="标签筛选，逗号分隔" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm flex-1" />
          <input v-model="searchQuery" placeholder="全文检索…" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm flex-1" />
          <button @click="loadCards" class="bg-primary text-white px-4 py-2 rounded-lg text-sm hover:bg-slate-800">查询</button>
        </div>
      </div>

      <!-- 卡片列表 -->
      <div class="space-y-4">
        <div v-for="card in cards" :key="card.id" :data-card-id="card.id" class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="flex items-start justify-between mb-2">
            <div class="text-xs text-slate-500 dark:text-slate-400 space-x-2">
              <span class="bg-slate-100 dark:bg-slate-700 px-2 py-0.5 rounded">{{ card.main_category }}</span>
              <span v-for="tag in card.tags" :key="tag" class="bg-blue-50 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300 px-2 py-0.5 rounded">{{ tag }}</span>
            </div>
            <div class="flex items-center space-x-2">
              <button @click="toggleBookmark('knowledge_card', card.id)" class="text-lg" :title="isBookmarked('knowledge_card', card.id) ? '取消收藏' : '收藏'">
                {{ isBookmarked('knowledge_card', card.id) ? '★' : '☆' }}
              </button>
              <span class="text-xs text-slate-400 dark:text-slate-500">v{{ card.latest_version }}</span>
            </div>
          </div>

          <div class="text-sm text-slate-800 dark:text-slate-200 mb-3 whitespace-pre-line">{{ card.card_content }}</div>

          <div class="flex flex-wrap gap-2 mb-3">
            <a v-for="(url, idx) in card.original_urls" :key="idx" :href="url" target="_blank" @click="onOpenCard(card)" class="text-xs text-blue-600 dark:text-blue-400 hover:underline">🔗 参考链接 {{ idx + 1 }}</a>
          </div>

          <!-- 个人备注 -->
          <div class="bg-slate-50 dark:bg-slate-700/50 rounded-lg p-3">
            <div class="text-xs font-medium text-slate-600 dark:text-slate-300 mb-1">个人备注</div>
            <textarea v-model="notes[card.id]" rows="2" class="w-full border dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 rounded-lg px-2 py-1 text-sm" placeholder="写下你的思考…"></textarea>
            <div class="flex justify-end mt-2">
              <button @click="saveNote(card.id)" class="text-xs bg-primary text-white px-3 py-1.5 rounded hover:bg-slate-800">保存备注</button>
            </div>
          </div>

          <!-- 相关卡片 -->
          <div v-if="card.related && card.related.length" class="mt-3 border-t dark:border-slate-700 pt-3">
            <div class="text-xs font-medium text-slate-600 dark:text-slate-300 mb-2">相关卡片</div>
            <div class="space-y-2">
              <div v-for="r in card.related" :key="r.id" class="text-xs text-slate-600 dark:text-slate-400 bg-slate-50 dark:bg-slate-700/50 rounded p-2 cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-700" @click="openRelatedCard(r.id)">
                <span class="font-medium">{{ r.main_category }}</span>
                <span class="ml-2">{{ r.card_content }}</span>
                <span class="ml-2 text-blue-600 dark:text-blue-400">{{ r.common_tags }} 个共同标签</span>
              </div>
            </div>
          </div>

          <!-- 历史版本（仅 owner） -->
          <div v-if="auth.isOwner && card.showHistory" class="mt-3 border-t dark:border-slate-700 pt-3">
            <div class="text-xs font-medium text-slate-600 dark:text-slate-300 mb-2">历史版本</div>
            <div v-for="h in card.history" :key="h.id" class="text-xs text-slate-500 dark:text-slate-400 mb-1">
              v{{ h.version }} · {{ formatDate(h.created_at) }}
            </div>
          </div>
          <div v-if="auth.isOwner" class="mt-2">
            <button @click="toggleHistory(card)" class="text-xs text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200">
              {{ card.showHistory ? '隐藏历史' : '查看历史' }}
            </button>
          </div>
        </div>
      </div>

      <div v-if="loading" class="text-center text-slate-500 dark:text-slate-400 py-8">加载中…</div>
      <div v-else-if="cards.length === 0" class="text-center text-slate-400 dark:text-slate-500 py-12">暂无知识卡片</div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import dayjs from 'dayjs'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const cards = ref([])
const notes = ref({})
const loading = ref(false)
const selectedCategory = ref('')
const tagQuery = ref('')
const searchQuery = ref('')
const bookmarkMap = ref({})

const categories = [
  '顶层国策体系',
  '货币政策&流动性',
  '财政政策体系',
  '产业政策',
  '宏观经济数据体系',
  '金融监管体系',
  '涉外经济&汇率&外资',
  '市场中长期逻辑推演库',
  '前沿科技成果库',
  '全球地缘政治&全球重大事件库',
  '探索订阅专题库'
]

function formatDate (d) {
  return d ? dayjs(d).format('YYYY-MM-DD HH:mm') : ''
}

async function loadCards () {
  loading.value = true
  let q = auth.supabase.from('knowledge_card').select('*')
  if (selectedCategory.value) {
    q = q.eq('main_category', selectedCategory.value)
  }
  if (tagQuery.value.trim()) {
    const tags = tagQuery.value.split(',').map(t => t.trim()).filter(Boolean)
    if (tags.length) {
      q = q.overlaps('tags', tags)
    }
  }
  if (searchQuery.value.trim()) {
    // 优先使用 RPC 全文检索；RPC 不存在时回退到 ILIKE
    try {
      const { data } = await auth.supabase.rpc('search_resources', {
        p_query: searchQuery.value.trim(),
        p_limit: 50
      })
      if (data) {
        // 搜索返回的是混合结果，需要把 knowledge_card 过滤出来
        const cardIds = data.filter(r => r.resource_type === 'knowledge_card').map(r => r.id)
        if (cardIds.length) {
          q = auth.supabase.from('knowledge_card').select('*').in('id', cardIds)
        } else {
          cards.value = []
          loading.value = false
          return
        }
      }
    } catch (e) {
      console.warn('search_resources rpc failed, fallback to ILIKE', e)
      q = q.ilike('card_content', `%${searchQuery.value.trim()}%`)
    }
  }
  const { data, error } = await q.order('updated_at', { ascending: false }).limit(50)
  if (error) {
    console.error('loadCards error:', error)
  } else {
    cards.value = (data || []).map(c => ({ ...c, showHistory: false, history: [], related: [] }))
    await loadNotes()
    await loadBookmarks()
    await loadRelatedForAll()
  }
  loading.value = false
}

async function loadNotes () {
  if (!cards.value.length) return
  const ids = cards.value.map(c => c.id)
  const { data, error } = await auth.supabase
    .from('user_card_note')
    .select('*')
    .in('card_id', ids)
    .eq('user_id', auth.user.id)
  if (error) {
    console.error('loadNotes error:', error)
    return
  }
  notes.value = {}
  for (const n of data || []) {
    notes.value[n.card_id] = n.note_content || ''
  }
}

async function loadBookmarks () {
  if (!cards.value.length) return
  const ids = cards.value.map(c => c.id)
  const { data } = await auth.supabase
    .from('user_bookmark')
    .select('resource_id')
    .eq('user_id', auth.user.id)
    .eq('resource_type', 'knowledge_card')
    .in('resource_id', ids)
  bookmarkMap.value = {}
  for (const b of data || []) {
    bookmarkMap.value[`knowledge_card:${b.resource_id}`] = true
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

async function loadRelatedForAll () {
  for (const card of cards.value) {
    try {
      const { data } = await auth.supabase.rpc('get_related_cards', {
        p_card_id: card.id,
        p_limit: 3
      })
      card.related = data || []
    } catch (e) {
      console.warn('get_related_cards failed', e)
      card.related = []
    }
  }
}

function openRelatedCard (id) {
  // 简单滚动到对应卡片位置；如果不在当前列表则重新搜索
  const el = document.getElementById ? null : null
  searchQuery.value = ''
  selectedCategory.value = ''
  tagQuery.value = ''
  loadCards().then(() => {
    // 加载完成后滚动到目标卡片
    setTimeout(() => {
      const target = document.querySelector(`[data-card-id="${id}"]`)
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }, 300)
  })
}

async function saveNote (cardId) {
  const content = notes.value[cardId] || ''
  const { error } = await auth.supabase.from('user_card_note').upsert({
    user_id: auth.user.id,
    card_id: cardId,
    note_content: content
  })
  if (error) {
    alert('保存失败：' + error.message)
  } else {
    alert('备注已保存')
  }
}

async function onOpenCard (card) {
  await auth.logBrowse('knowledge_card', card.id)
}

async function toggleHistory (card) {
  if (card.showHistory) {
    card.showHistory = false
    return
  }
  const { data, error } = await auth.supabase
    .from('knowledge_card_history')
    .select('*')
    .eq('card_id', card.id)
    .order('version', { ascending: false })
    .limit(10)
  if (!error) {
    card.history = data || []
    card.showHistory = true
  }
}

onMounted(() => {
  loadCards()
})
</script>
