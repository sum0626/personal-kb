import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/Login.vue'),
    meta: { public: true }
  },
  {
    path: '/trial-expired',
    name: 'TrialExpired',
    component: () => import('@/views/TrialExpired.vue'),
    meta: { public: true }
  },
  {
    path: '/',
    name: 'Today',
    component: () => import('@/views/Today.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/knowledge',
    name: 'Knowledge',
    component: () => import('@/views/Knowledge.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/subscribe',
    name: 'Subscribe',
    component: () => import('@/views/Subscribe.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/search',
    name: 'Search',
    component: () => import('@/views/Search.vue'),
    meta: { requiresAuth: true }
  },
  {
    path: '/admin',
    name: 'Admin',
    component: () => import('@/views/Admin.vue'),
    meta: { requiresAuth: true, requiresOwner: true }
  },
  {
    path: '/:pathMatch(.*)*',
    redirect: '/'
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach((to, from, next) => {
  const auth = useAuthStore()

  // 未登录且非公开页面 -> 登录页
  if (to.meta.requiresAuth && !auth.isLoggedIn) {
    next('/login')
    return
  }

  // trial 过期跳转
  if (to.meta.requiresAuth && auth.isExpiredTrial) {
    next('/trial-expired')
    return
  }

  // owner 专属页面
  if (to.meta.requiresOwner && auth.userRole !== 'owner') {
    next('/')
    return
  }

  // 已登录访问登录页 -> 首页
  if (to.meta.public && auth.isLoggedIn) {
    next('/')
    return
  }

  next()
})

export default router
