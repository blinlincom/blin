import { describe, expect, it } from 'vitest'
import { navigation } from '../src/modules/navigation'

describe('admin navigation', () => {
  it('does not expose removed businesses', () => {
    const text = JSON.stringify(navigation).toLowerCase()
    for (const removed of ['otc', 'gasfree', 'tron', '数字资产', '闪兑']) {
      expect(text).not.toContain(removed.toLowerCase())
    }
  })
})
