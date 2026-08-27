<template>
  <div class="min-h-screen bg-slate-50 dark:bg-slate-900 pb-20">
    <div class="max-w-5xl mx-auto px-4 py-6">
      <h2 class="text-xl font-bold mb-4 dark:text-white">管理员后台</h2>

      <!-- Owner 仪表盘 -->
      <div v-if="stats" class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4 mb-6">
        <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="text-xs text-slate-500 dark:text-slate-400">总新闻</div>
          <div class="text-2xl font-bold dark:text-white">{{ stats.total_news }}</div>
        </div>
        <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="text-xs text-slate-500 dark:text-slate-400">今日新闻</div>
          <div class="text-2xl font-bold dark:text-white">{{ stats.news_today }}</div>
        </div>
        <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="text-xs text-slate-500 dark:text-slate-400">知识卡片</div>
          <div class="text-2xl font-bold dark:text-white">{{ stats.total_cards }}</div>
        </div>
        <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="text-xs text-slate-500 dark:text-slate-400">活跃用户</div>
          <div class="text-2xl font-bold dark:text-white">{{ stats.active_users_today }}</div>
        </div>
        <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4">
          <div class="text-xs text-slate-500 dark:text-slate-400">活跃订阅</div>
          <div class="text-2xl font-bold dark:text-white">{{ stats.active_subscriptions }}</div>
        </div>
      </div>

      <!-- 创建试用账号（前端仅生成命令，实际由本地 Python 脚本执行） -->
      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-6">
        <h3 class="font-semibold mb-3 dark:text-white">创建 7 天试用账号</h3>
        <p class="text-xs text-slate-500 dark:text-slate-400 mb-3">
          出于安全，前端不持有 service_role_key。请在本机终端执行下方生成的命令。
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
          <input v-model="newUser.email" placeholder="邮箱" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm" />
          <input v-model="newUser.password" placeholder="密码" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm" />
          <input v-model="newUser.packages" placeholder="订阅包，逗号分隔（可选）" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 text-sm" />
        </div>
        <button @click="generateCommand" class="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-blue-700">
          生成创建命令
        </button>
        <div v-if="cliCommand" class="mt-3 bg-slate-900 text-green-400 text-xs p-3 rounded-lg break-all">
          {{ cliCommand }}
        </div>
      </div>

      <!-- 采集任务（管理员点击触发，本机 poller 执行） -->
      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-6">
        <h3 class="font-semibold mb-3 dark:text-white">新闻采集任务</h3>
        <p class="text-xs text-slate-500 dark:text-slate-400 mb-3">
          点击后会在数据库创建 pending 任务。请确保本机已运行 <code>python scripts/poller.py</code>，poller 才会真正执行采集。
        </p>
        <div class="flex items-center gap-3 mb-4">
          <button
            @click="triggerCollection"
            :disabled="collecting"
            class="bg-emerald-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-emerald-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {{ collecting ? '已提交...' : '立即采集' }}
          </button>
          <button
            @click="loadCollectionJobs"
            class="bg-slate-200 dark:bg-slate-700 text-slate-700 dark:text-slate-200 px-4 py-2 rounded-lg text-sm hover:bg-slate-300 dark:hover:bg-slate-600"
          >
            刷新列表
          </button>
        </div>
        <p class="text-xs text-slate-400 dark:text-slate-500 mb-2">
          手动命令：.venv\Scripts\activate && python scripts/collect_daily.py
        </p>
        <div class="max-h-64 overflow-y-auto">
          <div v-for="job in collectionJobs" :key="job.id" class="text-xs border-b last:border-0 dark:border-slate-700 py-2">
            <div class="flex items-center justify-between">
              <span class="font-medium dark:text-slate-200">{{ formatDate(job.created_at) }}</span>
              <span
                class="px-2 py-0.5 rounded text-xs"
                :class="jobStatusClass(job.status)"
              >
                {{ jobStatusText(job.status) }}
              </span>
            </div>
            <div class="text-slate-500 dark:text-slate-400 mt-1">
              来源：{{ job.source_type || 'all' }}
              <span v-if="job.result_summary" class="ml-2">
                结果：{{ formatCollectionSummary(job.result_summary) }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- 用户列表 -->
      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-6 overflow-x-auto">
        <h3 class="font-semibold mb-3 dark:text-white">用户管理</h3>
        <table class="min-w-full text-sm">
          <thead>
            <tr class="text-left text-slate-500 dark:text-slate-400 border-b dark:border-slate-700">
              <th class="pb-2">邮箱</th>
              <th class="pb-2">角色</th>
              <th class="pb-2">状态</th>
              <th class="pb-2">试用到期</th>
              <th class="pb-2">订阅包</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="u in users" :key="u.id" class="border-b last:border-0 dark:border-slate-700">
              <td class="py-2 dark:text-slate-300">{{ u.email }}</td>
              <td class="py-2">
                <select v-model="u.user_role" @change="updateUser(u, 'p_user_role', u.user_role)" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded px-2 py-1 text-xs">
                  <option value="owner">owner</option>
                  <option value="member">member</option>
                  <option value="trial">trial</option>
                </select>
              </td>
              <td class="py-2">
                <button @click="toggleActive(u)" class="px-2 py-1 rounded text-xs" :class="u.is_active ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'">
                  {{ u.is_active ? '启用' : '禁用' }}
                </button>
              </td>
              <td class="py-2">
                <input v-model="u.trial_expire_at" type="datetime-local" @change="updateExpire(u)" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded px-2 py-1 text-xs" />
              </td>
              <td class="py-2">
                <input v-model="u.assigned_packages_str" @change="updatePackages(u)" class="border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded px-2 py-1 text-xs w-32" />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 登录日志 -->
      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-6">
        <h3 class="font-semibold mb-3 dark:text-white">登录审计</h3>
        <div class="space-y-2 max-h-64 overflow-y-auto">
          <div v-for="log in loginLogs" :key="log.id" class="text-xs text-slate-600 dark:text-slate-400 border-b last:border-0 pb-1">
            <span class="font-medium">{{ formatDate(log.login_time) }}</span>
            <span class="ml-2">{{ log.email }}</span>
            <span class="ml-2 text-slate-400 dark:text-slate-500">{{ log.user_agent }}</span>
          </div>
        </div>
        <button @click="loadLoginLogs" class="mt-3 text-xs text-blue-600 dark:text-blue-400 hover:underline">刷新</button>
      </div>

      <!-- 浏览日志 -->
      <div class="bg-white dark:bg-slate-800 rounded-xl shadow p-4 mb-6">
        <h3 class="font-semibold mb-3 dark:text-white">浏览行为日志（最近 50 条）</h3>
        <div class="space-y-2 max-h-64 overflow-y-auto">
          <div v-for="log in browseLogs" :key="log.id" class="text-xs text-slate-600 dark:text-slate-400 border-b last:border-0 pb-1">
            <span class="font-medium">{{ formatDate(log.browse_time) }}</span>
            <span class="ml-2">{{ log.resource_type }}</span>
            <span class="ml-2 text-slate-400 dark:text-slate-500">{{ log.resource_id }}</span>
          </div>
        </div>
        <button @click="loadBrowseLogs" class="mt-3 text-xs text-blue-600 dark:text-blue-400 hover:underline">刷新</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import dayjs from 'dayjs'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()

const users = ref([])
const loginLogs = ref([])
const browseLogs = ref([])
const newUser = ref({ email: '', password: '', packages: '' })
const cliCommand = ref('')
const stats = ref(null)
const collectionJobs = ref([])
const collecting = ref(false)

function formatDate (d) {
  return d ? dayjs(d).format('YYYY-MM-DD HH:mm') : ''
}

function formatDateInput (d) {
  return d ? dayjs(d).format('YYYY-MM-DDTHH:mm') : ''
}

async function loadStats () {
  const { data, error } = await auth.supabase.rpc('get_admin_dashboard_stats')
  if (error) {
    console.error('loadStats error:', error)
    return
  }
  stats.value = data
}

async function loadUsers () {
  const { data, error } = await auth.supabase.rpc('get_all_users')
  if (error) {
    console.error('loadUsers error:', error)
    return
  }
  users.value = (data || []).map(u => ({
    ...u,
    trial_expire_at: formatDateInput(u.trial_expire_at),
    assigned_packages_str: (u.assigned_packages || []).join(', ')
  }))
}

async function loadLoginLogs () {
  const { data, error } = await auth.supabase
    .from('login_log')
    .select('*')
    .order('login_time', { ascending: false })
    .limit(100)
  if (error) {
    console.error('loadLoginLogs error:', error)
  } else {
    loginLogs.value = data || []
  }
}

async function loadBrowseLogs () {
  const { data, error } = await auth.supabase
    .from('browse_log')
    .select('*')
    .order('browse_time', { ascending: false })
    .limit(50)
  if (error) {
    console.error('loadBrowseLogs error:', error)
  } else {
    browseLogs.value = data || []
  }
}

function generateCommand () {
  const packages = newUser.value.packages.split(',').map(s => s.trim()).filter(Boolean)
  const pkgArg = packages.length ? ` --packages ${packages.join(' ')}` : ''
  cliCommand.value = `python scripts/create_trial_user.py --email ${newUser.value.email} --password ${newUser.value.password}${pkgArg}`
}

async function updateUser (u, field, value) {
  const payload = { [field]: value }
  if (field === 'p_trial_expire_at') {
    payload[field] = value ? dayjs(value).toISOString() : null
  }
  const { error } = await auth.supabase.rpc('admin_update_user', {
    p_user_id: u.id,
    ...payload
  })
  if (error) {
    alert('更新失败：' + error.message)
  }
}

async function toggleActive (u) {
  const next = !u.is_active
  u.is_active = next
  await updateUser(u, 'p_is_active', next)
}

async function updateExpire (u) {
  await updateUser(u, 'p_trial_expire_at', dayjs(u.trial_expire_at).toISOString())
}

async function updatePackages (u) {
  const packages = u.assigned_packages_str.split(',').map(s => s.trim()).filter(Boolean)
  await updateUser(u, 'p_assigned_packages', packages)
}

async function loadCollectionJobs () {
  const { data, error } = await auth.supabase
    .from('collection_jobs')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(10)
  if (error) {
    console.error('loadCollectionJobs error:', error)
  } else {
    collectionJobs.value = data || []
  }
}

async function triggerCollection () {
  collecting.value = true
  const { error } = await auth.supabase
    .from('collection_jobs')
    .insert({
      status: 'pending',
      source_type: 'all',
      result_summary: {}
    })
  if (error) {
    alert('提交采集任务失败：' + error.message)
    console.error('triggerCollection error:', error)
  } else {
    await loadCollectionJobs()
    alert('采集任务已提交，请确保本机 poller 正在运行。')
  }
  collecting.value = false
}

function jobStatusText (status) {
  const map = {
    pending: '等待中',
    running: '执行中',
    done: '已完成',
    failed: '失败'
  }
  return map[status] || status
}

function jobStatusClass (status) {
  const map = {
    pending: 'bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-200',
    running: 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-200',
    done: 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-200',
    failed: 'bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-200'
  }
  return map[status] || 'bg-slate-100 text-slate-700'
}

function formatCollectionSummary (summary) {
  if (!summary) return ''
  if (summary.success === false) {
    return '执行失败'
  }
  const news = summary.news_count ?? summary.news ?? 0
  const cands = summary.candidate_count ?? summary.candidates ?? 0
  return `${news} 条新闻 / ${cands} 个候选话题`
}

onMounted(() => {
  loadStats()
  loadUsers()
  loadLoginLogs()
  loadBrowseLogs()
  loadCollectionJobs()
})
</script>
