// 终生成长知识库 PWA Service Worker
// 当前版本仅做基础注册与占位，离线缓存能力后续可扩展
const CACHE_NAME = 'personal-kb-v1'

self.addEventListener('install', (event) => {
  console.log('[SW] install')
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  console.log('[SW] activate')
  event.waitUntil(self.clients.claim())
})

self.addEventListener('fetch', (event) => {
  // 目前不拦截请求，保持纯在线模式
  // 未来可在此缓存静态资源与已加载的 API 数据
})
