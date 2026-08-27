<template>
  <div class="min-h-screen flex items-center justify-center bg-slate-100 dark:bg-slate-950 px-4">
    <div class="w-full max-w-sm bg-white dark:bg-slate-800 rounded-xl shadow p-6 text-center">
      <h1 class="text-xl font-bold text-red-600 dark:text-red-400 mb-4">试用已到期</h1>
      <p class="text-slate-600 dark:text-slate-300 mb-6">您的 7 天试用账号已过期，请联系管理员续期或升级。</p>
      <button @click="backToLogin" class="w-full bg-primary text-white py-2 rounded-lg hover:bg-slate-800">
        返回登录页
      </button>
    </div>
  </div>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const auth = useAuthStore()

async function backToLogin () {
  await auth.logout()
  router.replace('/login')
}
</script>
