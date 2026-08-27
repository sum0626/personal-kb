import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true
  }
})

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null)
  const profile = ref(null)
  const session = ref(null)

  const isLoggedIn = computed(() => !!user.value)
  const userRole = computed(() => profile.value?.user_role || null)
  const isOwner = computed(() => userRole.value === 'owner')
  const isTrial = computed(() => userRole.value === 'trial')
  const isMember = computed(() => userRole.value === 'member')
  const isExpiredTrial = computed(() => {
    if (!isTrial.value) return false
    if (!profile.value?.trial_expire_at) return false
    return new Date(profile.value.trial_expire_at) < new Date()
  })

  async function restoreSession () {
    const { data } = await supabase.auth.getSession()
    if (data.session) {
      await setSession(data.session)
    }
  }

  async function setSession (s) {
    session.value = s
    user.value = s.user
    await fetchProfile()
  }

  async function fetchProfile () {
    if (!user.value) return
    const { data, error } = await supabase
      .from('user_profile')
      .select('*')
      .eq('user_id', user.value.id)
      .single()

    if (error) {
      console.error('fetchProfile error:', error)
      return
    }
    profile.value = data
  }

  async function login (email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    await setSession(data.session)
    return data
  }

  async function logout () {
    await supabase.auth.signOut()
    user.value = null
    profile.value = null
    session.value = null
  }

  async function logBrowse (type, id) {
    if (!user.value || !id) return
    try {
      await supabase.from('browse_log').insert({
        user_id: user.value.id,
        resource_type: type,
        resource_id: id
      })
    } catch (e) {
      console.error('logBrowse error:', e)
    }
  }

  async function logLogin (ua, ip) {
    if (!user.value) return
    try {
      await supabase.from('login_log').insert({
        user_id: user.value.id,
        user_agent: ua,
        ip_addr: ip
      })
    } catch (e) {
      console.error('logLogin error:', e)
    }
  }

  return {
    user,
    profile,
    session,
    supabase,
    isLoggedIn,
    userRole,
    isOwner,
    isTrial,
    isMember,
    isExpiredTrial,
    restoreSession,
    setSession,
    fetchProfile,
    login,
    logout,
    logBrowse,
    logLogin
  }
})
