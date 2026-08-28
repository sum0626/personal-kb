<template>
  <div class="text-sm">
    <div class="font-medium text-slate-700 dark:text-slate-200 mb-2">分类目录</div>
    <ul class="space-y-1">
      <li>
        <button
          @click="select('')"
          class="w-full text-left px-2 py-1 rounded transition-colors"
          :class="selectedPath === '' ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300' : 'hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-600 dark:text-slate-300'"
        >
          全部分类
        </button>
      </li>
      <CategoryTreeNode
        v-for="node in treeData"
        :key="node.id"
        :node="node"
        :selected-path="selectedPath"
        :level="0"
        @select="select"
      />
    </ul>
  </div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import CategoryTreeNode from './CategoryTreeNode.vue'

const auth = useAuthStore()
const treeData = ref([])
const selectedPath = ref('')
const emit = defineEmits(['select'])

async function loadTree () {
  try {
    const { data, error } = await auth.supabase.rpc('get_category_tree')
    if (error) {
      console.error('loadTree error:', error)
      return
    }
    treeData.value = buildTree(data || [])
  } catch (e) {
    console.error('loadTree exception:', e)
  }
}

function buildTree (flat) {
  const map = {}
  const roots = []
  for (const item of flat) {
    map[item.id] = { ...item, children: [] }
  }
  for (const item of flat) {
    if (item.parent_id && map[item.parent_id]) {
      map[item.parent_id].children.push(map[item.id])
    } else {
      roots.push(map[item.id])
    }
  }
  return roots
}

function select (path) {
  selectedPath.value = path || ''
  emit('select', selectedPath.value)
}

onMounted(() => {
  loadTree()
})
</script>
