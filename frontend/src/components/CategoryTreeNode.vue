<template>
  <li>
    <div class="flex items-center">
      <button
        v-if="node.children && node.children.length"
        @click="expanded = !expanded"
        class="w-5 h-5 flex items-center justify-center text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
      >
        {{ expanded ? '−' : '+' }}
      </button>
      <span v-else class="w-5"></span>
      <button
        @click="select(node.full_path)"
        class="flex-1 text-left px-2 py-1 rounded transition-colors truncate"
        :class="selectedPath === node.full_path || (selectedPath && selectedPath.startsWith(node.full_path + '/')) ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300' : 'hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-600 dark:text-slate-300'"
        :style="{ paddingLeft: `${level * 12 + 8}px` }"
      >
        {{ node.name }}
        <span v-if="node.children_count" class="text-xs text-slate-400 dark:text-slate-500 ml-1">({{ node.children_count }})</span>
      </button>
    </div>
    <ul v-if="expanded && node.children && node.children.length" class="mt-1 space-y-1">
      <CategoryTreeNode
        v-for="child in node.children"
        :key="child.id"
        :node="child"
        :selected-path="selectedPath"
        :level="level + 1"
        @select="$emit('select', $event)"
      />
    </ul>
  </li>
</template>

<script setup>
import { ref, watch } from 'vue'

const props = defineProps({
  node: { type: Object, required: true },
  selectedPath: { type: String, default: '' },
  level: { type: Number, default: 0 }
})

const emit = defineEmits(['select'])
const expanded = ref(false)

watch(() => props.selectedPath, (newPath) => {
  // 如果当前选中路径在该节点下，自动展开
  if (newPath && newPath.startsWith(props.node.full_path + '/')) {
    expanded.value = true
  }
}, { immediate: true })

function select (path) {
  emit('select', path)
}
</script>
