import { createRouter, createWebHistory } from 'vue-router'
import AdminShell from '../app/AdminShell.vue'
import DashboardView from '../views/DashboardView.vue'
import LoginView from '../views/LoginView.vue'
import WalletView from '../views/WalletView.vue'
import SettingsView from '../views/SettingsView.vue'
import UsersView from '../views/UsersView.vue'
import GroupsView from '../views/GroupsView.vue'
import MessagesView from '../views/MessagesView.vue'
import MomentsView from '../views/MomentsView.vue'
import ServiceAccountsView from '../views/ServiceAccountsView.vue'
import CallsView from '../views/CallsView.vue'
import AuditView from '../views/AuditView.vue'
import OperationsView from '../views/OperationsView.vue'
import { useAuthStore } from '../stores/auth'

const child = (path: string, title: string) => ({ path, component: DashboardView, props: { title } })

export const router = createRouter({
  history: createWebHistory(),
  routes: [{
    path: '/', component: AdminShell, children: [
      {path:'',component:DashboardView,meta:{permission:'dashboard:read'}},{path:'users',component:UsersView,meta:{permission:'user:read'}},{path:'contacts',component:GroupsView,meta:{permission:'group:read'}},
      {path:'messages',component:MessagesView,meta:{permission:'message:audit'}}, { path: 'wallet', component: WalletView, meta: { permission: 'wallet:read' } },
      {path:'service-accounts',component:ServiceAccountsView,meta:{permission:'service_account:read'}},{path:'moments',component:MomentsView,meta:{permission:'moment:read'}},
      {path:'calls',component:CallsView,meta:{permission:'call:read'}}, child('moderation', '内容审核'), {path:'operations',component:OperationsView,meta:{permission:'moderation:read'}}, { path: 'settings', component: SettingsView, meta: { permission: 'config:read' } },{path:'audit',component:AuditView,meta:{permission:'audit:read'}},
    ],
  }, {
    path: '/login', component: LoginView, meta: { public: true },
  }],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (to.meta.public) return auth.authenticated ? '/' : true
  if (!auth.authenticated && !(await auth.restore())) return { path: '/login', query: { redirect: to.fullPath } }
  const permission = to.meta.permission as string | undefined
  if (!auth.can(permission)) return '/'
  return true
})
