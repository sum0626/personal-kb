<template>
  <NavBar v-if="auth.isLoggedIn && !auth.isExpiredTrial" />
  <router-view />
</template>

<script setup>
import { onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import NavBar from '@/components/NavBar.vue'

const auth = useAuthStore()
onMounted(() => {
  auth.restoreSession()
})
</script>
