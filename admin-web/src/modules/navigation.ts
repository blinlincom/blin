export interface NavigationItem {
  label: string
  path: string
  permission?: string
}

export const navigation: NavigationItem[] = [
  { label: '工作台', path: '/' },
  { label: '用户与设备', path: '/users', permission: 'user:read' },
  { label: '好友与群聊', path: '/contacts', permission: 'group:read' },
  { label: '消息审计', path: '/messages', permission: 'message:audit' },
  { label: '平台钱包', path: '/wallet', permission: 'wallet:read' },
  { label: '服务号', path: '/service-accounts', permission: 'service_account:read' },
  { label: '朋友圈', path: '/moments', permission: 'moment:read' },
  { label: '音视频', path: '/calls', permission: 'call:read' },
  { label: '内容审核', path: '/moderation', permission: 'moderation:read' },
  { label: '内容与交易', path: '/operations', permission: 'moderation:read' },
  { label: '系统设置', path: '/settings', permission: 'config:read' },
  { label: '审计日志', path: '/audit', permission: 'audit:read' },
]
