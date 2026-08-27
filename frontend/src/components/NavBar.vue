<template>
  <nav class="bg-primary text-white dark:bg-slate-950 dark:border-b dark:border-slate-800 sticky top-0 z-50 shadow">
    <div class="max-w-5xl mx-auto px-4 h-14 flex items-center justify-between">
      <div class="font-bold text-lg truncate">终生成长知识库</div>
      <div class="flex items-center space-x-3 text-sm overflow-x-auto no-scrollbar">
        <router-link v-if="isLoggedIn" to="/" class="opacity-90 hover:opacity-100 whitespace-nowrap">今日</router-link>
        <router-link v-if="isLoggedIn" to="/knowledge" class="opacity-90 hover:opacity-100 whitespace-nowrap">知识库</router-link>
        <router-link v-if="isLoggedIn" to="/search" class="opacity-90 hover:opacity-100 whitespace-nowrap">搜索</router-link>
        <router-link v-if="isLoggedIn" to="/subscribe" class="opacity-90 hover:opacity-100 whitespace-nowrap">订阅</router-link>
        <router-link v-if="isOwner" to="/admin" class="opacity-90 hover:opacity-100 whitespace-nowrap text-yellow-300">管理</router-link>
        <button @click="theme.toggle" class="opacity-90 hover:opacity-100 whitespace-nowrap" :title="theme.isDark ? '切换浅色' : '切换深色'">
          {{ theme.isDark ? '☀' : '☾' }}
        </button>
        <button v-if="isLoggedIn" @click="logout" class="opacity-90 hover:opacity-100 whitespace-nowrap">退出</button>
      </div>
    </div>
  </nav>
</template>

<script setup>
import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useThemeStore } from '@/stores/theme'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const theme = useThemeStore()
const router = useRouter()

const isLoggedIn = computed(() => auth.isLoggedIn)
const isOwner = computed(() => auth.isOwner)

async function logout () {
  await auth.logout()
  router.push('/login')
}
</script>

<style scoped>
.router-link-active {
  font-weight: 600;
  opacity: 1;
}
.no-scrollbar::-webkit-scrollbar {
  display: none;
}
</style>
