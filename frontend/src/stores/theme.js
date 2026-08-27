import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

const STORAGE_KEY = 'personal-kb-dark-mode'

export const useThemeStore = defineStore('theme', () => {
  const isDark = ref(false)

  function init () {
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved !== null) {
      isDark.value = saved === 'true'
    } else {
      isDark.value = window.matchMedia('(prefers-color-scheme: dark)').matches
    }
    apply()
  }

  function apply () {
    if (isDark.value) {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
  }

  function toggle () {
    isDark.value = !isDark.value
    apply()
    localStorage.setItem(STORAGE_KEY, String(isDark.value))
  }

  watch(isDark, apply)

  return { isDark, init, toggle, apply }
})
