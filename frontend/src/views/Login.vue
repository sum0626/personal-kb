<template>
  <div class="min-h-screen flex items-center justify-center bg-slate-100 dark:bg-slate-950 px-4">
    <div class="w-full max-w-sm bg-white dark:bg-slate-800 rounded-xl shadow p-6">
      <h1 class="text-2xl font-bold text-center mb-2 dark:text-white">终生成长知识库</h1>
      <p class="text-sm text-slate-500 dark:text-slate-400 text-center mb-6">宏观 · 政策 · 科技 · 地缘</p>
      <form @submit.prevent="handleLogin">
        <div class="mb-4">
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">邮箱</label>
          <input v-model="email" type="email" required class="w-full border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent" />
        </div>
        <div class="mb-6">
          <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">密码</label>
          <input v-model="password" type="password" required class="w-full border dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-accent" />
        </div>
        <button type="submit" :disabled="loading" class="w-full bg-primary text-white py-2 rounded-lg hover:bg-slate-800 disabled:opacity-50">
          {{ loading ? '登录中…' : '登录' }}
        </button>
        <p v-if="error" class="mt-4 text-sm text-red-600 dark:text-red-400 text-center">{{ error }}</p>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const auth = useAuthStore()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')

onMounted(async () => {
  await auth.restoreSession()
  if (auth.isLoggedIn) {
    if (auth.isExpiredTrial) {
      router.replace('/trial-expired')
    } else {
      router.replace('/')
    }
  }
})

async function handleLogin () {
  loading.value = true
  error.value = ''
  try {
    await auth.login(email.value, password.value)
    // 记录登录信息（IP 由后端/RLS 层处理，前端只能拿到 UA）
    await auth.logLogin(navigator.userAgent, null)
    if (auth.isExpiredTrial) {
      router.replace('/trial-expired')
    } else {
      router.replace('/')
    }
  } catch (e) {
    error.value = e.message || '登录失败'
  } finally {
    loading.value = false
  }
}
</script>
