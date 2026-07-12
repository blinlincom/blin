<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
import { navigation } from '../modules/navigation'
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth=useAuthStore();const router=useRouter()
const visibleNavigation=computed(()=>navigation.filter((item)=>auth.can(item.permission)))
async function logout(){await auth.logout();await router.replace('/login')}
</script>

<template>
  <div class="shell">
    <aside>
      <div class="brand">BIM</div>
      <nav>
        <RouterLink v-for="item in visibleNavigation" :key="item.path" :to="item.path">
          {{ item.label }}
        </RouterLink>
      </nav>
    </aside>
    <main>
      <header><strong>BIM 管理后台</strong><div class="account"><span>{{ auth.admin?.username }}</span><button type="button" @click="logout">退出</button></div></header>
      <section><RouterView /></section>
    </main>
  </div>
</template>

<style scoped>
.shell { min-height: 100vh; display: grid; grid-template-columns: 224px minmax(0, 1fr); }
aside { background: #171a21; color: white; padding: 20px 12px; }
.brand { font-size: 22px; font-weight: 800; padding: 0 12px 22px; }
nav { display: grid; gap: 4px; }
nav a { color: #bec4cf; text-decoration: none; padding: 10px 12px; border-radius: var(--bim-radius); }
nav a.router-link-active { color: white; background: #2b303b; }
main { min-width: 0; }
header { height: 56px; display: flex; align-items: center; justify-content: space-between; padding: 0 24px; background: var(--bim-surface); border-bottom: 1px solid var(--bim-border); }
header button { border: 0; background: transparent; color: var(--bim-muted); }
.account { display: flex; align-items: center; gap: 14px; color: var(--bim-muted); font-size: 14px; }
section { padding: 24px; }
@media (max-width: 720px) { .shell { grid-template-columns: 72px minmax(0, 1fr); } .brand { font-size: 16px; padding-left: 6px; } nav a { font-size: 0; min-height: 40px; } }
</style>
