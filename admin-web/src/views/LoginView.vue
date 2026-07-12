<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ApiError } from '../api/client'
import { useAuthStore } from '../stores/auth'

const username = ref('')
const password = ref('')
const error = ref('')
const submitting = ref(false)
const auth = useAuthStore()
const router = useRouter()

async function submit() {
  error.value = ''
  submitting.value = true
  try { await auth.login(username.value, password.value); await router.replace('/') }
  catch (reason) { error.value = reason instanceof ApiError ? reason.message : '登录失败，请稍后重试' }
  finally { submitting.value = false }
}
</script>

<template>
  <main class="login-page">
    <form class="login-panel" @submit.prevent="submit">
      <div class="brand">BIM</div>
      <h1>管理后台</h1>
      <label>管理员账号<input v-model.trim="username" autocomplete="username" required /></label>
      <label>密码<input v-model="password" type="password" autocomplete="current-password" required /></label>
      <p v-if="error" role="alert">{{ error }}</p>
      <button type="submit" :disabled="submitting">{{ submitting ? '登录中...' : '登录' }}</button>
    </form>
  </main>
</template>

<style scoped>
.login-page{min-height:100vh;display:grid;place-items:center;padding:24px;background:#f3f5f8}.login-panel{width:min(380px,100%);padding:32px;background:#fff;border:1px solid var(--bim-border)}.brand{font-size:28px;font-weight:800;color:var(--bim-primary)}h1{margin:8px 0 28px;font-size:20px}label{display:grid;gap:8px;margin:0 0 18px;color:var(--bim-muted);font-size:14px}input{height:42px;padding:0 12px;border:1px solid var(--bim-border);outline:none}input:focus{border-color:var(--bim-primary)}button{width:100%;height:42px;border:0;background:var(--bim-primary);color:#fff}button:disabled{opacity:.6}p{color:var(--bim-danger);font-size:14px}
</style>
