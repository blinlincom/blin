import { defineStore } from 'pinia'
import { request } from '../api/client'

export interface AdminSession { id: number; username: string; permissions: string[] }
interface LoginResult { access_token: string; refresh_token: string; expires_at: string; admin: AdminSession }

export const useAuthStore = defineStore('auth', {
  state: () => ({ admin: null as AdminSession | null, loading: false }),
  getters: { authenticated: (state) => state.admin !== null },
  actions: {
    async login(username: string, password: string) {
      const result = await request<LoginResult>('/v1/auth/login', { method: 'POST', body: JSON.stringify({ username, password }) })
      sessionStorage.setItem('bim.admin.access_token', result.access_token)
      sessionStorage.setItem('bim.admin.refresh_token', result.refresh_token)
      this.admin = result.admin
    },
    async restore() {
      if (!sessionStorage.getItem('bim.admin.access_token')) return false
      this.loading = true
      try { this.admin = await request<AdminSession>('/v1/auth/session'); return true }
      catch { this.clear(); return false }
      finally { this.loading = false }
    },
    async logout() {
      try { await request('/v1/auth/logout', { method: 'POST' }) } finally { this.clear() }
    },
    clear() { sessionStorage.removeItem('bim.admin.access_token'); sessionStorage.removeItem('bim.admin.refresh_token'); this.admin = null },
    can(permission?: string) { return !permission || this.admin?.permissions.includes(permission) === true },
  },
})
