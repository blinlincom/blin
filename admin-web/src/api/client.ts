export interface Envelope<T> { code: string; message: string; data?: T; request_id?: string }

const baseURL = import.meta.env.VITE_ADMIN_API_BASE ?? '/admin-api'

export class ApiError extends Error {
  constructor(public code: string, message: string, public status: number) { super(message) }
}

let refreshPromise: Promise<boolean> | null = null

async function refreshAccessToken(): Promise<boolean> {
  const refreshToken = sessionStorage.getItem('bim.admin.refresh_token')
  if (!refreshToken) return false
  if (!refreshPromise) {
    refreshPromise = fetch(`${baseURL}/v1/auth/refresh`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken }),
    }).then(async (response) => {
      if (!response.ok) return false
      const payload = await response.json() as Envelope<{ access_token: string; refresh_token: string }>
      if (payload.code !== 'OK' || !payload.data) return false
      sessionStorage.setItem('bim.admin.access_token', payload.data.access_token)
      sessionStorage.setItem('bim.admin.refresh_token', payload.data.refresh_token)
      return true
    }).finally(() => { refreshPromise = null })
  }
  return refreshPromise
}

export async function request<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  const token = sessionStorage.getItem('bim.admin.access_token')
  const headers = new Headers(init.headers)
  headers.set('Accept', 'application/json')
  if (init.body) headers.set('Content-Type', 'application/json')
  if (token) headers.set('Authorization', `Bearer ${token}`)
  const response = await fetch(`${baseURL}${path}`, { ...init, headers, credentials: 'same-origin' })
  const payload = await response.json() as Envelope<T>
  if (response.status === 401 && retry && !path.endsWith('/login') && !path.endsWith('/refresh') && await refreshAccessToken()) {
    return request<T>(path, init, false)
  }
  if (!response.ok || payload.code !== 'OK') throw new ApiError(payload.code, payload.message, response.status)
  return payload.data as T
}
