<template>
  <div class="min-h-screen bg-slate-50 dark:bg-slate-900 pb-20">
    <div class="max-w-5xl mx-auto px-4 py-6">
      <h2 class="text-xl font-bold mb-4 dark:text-white">订阅专题</h2>

      <div class="space-y-4">
        <div v-for="task in tasks" :key="task.id" class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="flex items-start justify-between mb-2">
            <div>
              <div class="font-semibold dark:text-slate-100">{{ task.topic_name }}</div>
              <div class="text-xs text-slate-500 dark:text-slate-400 mt-1">
                <span class="bg-slate-100 dark:bg-slate-700 px-2 py-0.5 rounded">{{ taskTypeLabel(task.task_type) }}</span>
                <span class="bg-blue-50 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300 px-2 py-0.5 rounded">{{ task.status }}</span>
                <span class="ml-2">已推送 {{ task.day_count }} / {{ task.task_type === 'short' ? task.max_cycle : '∞' }} 天</span>
              </div>
            </div>
          </div>

          <!-- 进度条 -->
          <div class="w-full bg-slate-200 dark:bg-slate-700 rounded-full h-2 mb-3" v-if="task.task_type === 'short'">
            <div class="bg-blue-600 h-2 rounded-full transition-all" :style="{ width: Math.min(100, (task.day_count / task.max_cycle) * 100) + '%' }"></div>
          </div>

          <!-- 时间轴日程条 -->
          <div v-if="task.task_type === 'short'" class="flex items-center space-x-1 mb-3 overflow-x-auto no-scrollbar">
            <div v-for="day in task.max_cycle" :key="day" class="flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center text-xs"
                 :class="day <= task.day_count ? 'bg-blue-600 text-white' : 'bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-400'">
              {{ day }}
            </div>
          </div>

          <div class="text-sm text-slate-700 dark:text-slate-300 mb-3">启动于 {{ formatDate(task.start_day) }}</div>

          <!-- 7天专题到期操作 -->
          <div v-if="auth.isOwner && task.task_type === 'short' && task.day_count >= task.max_cycle && task.status === 'active'" class="grid grid-cols-2 sm:grid-cols-4 gap-2">
            <button @click="renewTask(task, 'perpetual')" class="text-xs bg-green-600 text-white py-2 rounded hover:bg-green-700">永续</button>
            <button @click="renewTask(task, 'renew7')" class="text-xs bg-blue-600 text-white py-2 rounded hover:bg-blue-700">续7天</button>
            <button @click="renewTask(task, 'archive')" class="text-xs bg-slate-600 text-white py-2 rounded hover:bg-slate-700">归档</button>
            <button @click="renewTask(task, 'delete')" class="text-xs bg-red-600 text-white py-2 rounded hover:bg-red-700">删除</button>
          </div>

          <!-- 长期跟踪手动关闭 -->
          <div v-if="auth.isOwner && task.task_type === 'long' && task.status === 'active'" class="flex space-x-2">
            <button @click="renewTask(task, 'archive')" class="text-xs bg-slate-600 text-white py-2 px-3 rounded hover:bg-slate-700">归档</button>
            <button @click="renewTask(task, 'delete')" class="text-xs bg-red-600 text-white py-2 px-3 rounded hover:bg-red-700">删除</button>
          </div>

          <div v-if="task.reference_urls && task.reference_urls.length" class="mt-3 flex flex-wrap gap-2">
            <a v-for="(url, idx) in task.reference_urls" :key="idx" :href="url" target="_blank" class="text-xs text-blue-600 dark:text-blue-400 hover:underline">🔗 参考 {{ idx + 1 }}</a>
          </div>
        </div>
      </div>

      <div v-if="loading" class="text-center text-slate-500 dark:text-slate-400 py-8">加载中…</div>
      <div v-else-if="tasks.length === 0" class="text-center text-slate-400 dark:text-slate-500 py-12">暂无订阅专题</div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import dayjs from 'dayjs'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const tasks = ref([])
const loading = ref(false)

function taskTypeLabel (type) {
  return type === 'long' ? '长期跟踪' : '7天专题'
}

function formatDate (d) {
  return d ? dayjs(d).format('YYYY-MM-DD') : ''
}

async function loadTasks () {
  loading.value = true
  const { data, error } = await auth.supabase
    .from('subscribe_task')
    .select('*')
    .in('status', ['active', 'archive'])
    .order('created_at', { ascending: false })
  if (error) {
    console.error('loadTasks error:', error)
  } else {
    tasks.value = data || []
  }
  loading.value = false
}

async function renewTask (task, action) {
  const { error } = await auth.supabase.rpc('renew_or_archive_subscription', {
    p_task_id: task.id,
    p_action: action
  })
  if (error) {
    alert('操作失败：' + error.message)
    return
  }
  await loadTasks()
}

onMounted(() => {
  loadTasks()
})
</script>

<style scoped>
.no-scrollbar::-webkit-scrollbar {
  display: none;
}
</style>
