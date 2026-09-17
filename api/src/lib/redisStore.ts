import { Redis } from 'ioredis'
import type { MetricsByDate } from '../types.js'

export const METRICS_CACHE_KEY = 'metrics:last14'

export interface RedisLike {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<unknown>
}

export interface MetricsStore {
  get(): Promise<MetricsByDate | null>
  set(metrics: MetricsByDate): Promise<void>
}

export function createMetricsStore(client: RedisLike): MetricsStore {
  return {
    async get() {
      const raw = await client.get(METRICS_CACHE_KEY)
      return raw === null ? null : (JSON.parse(raw) as MetricsByDate)
    },
    async set(metrics: MetricsByDate) {
      await client.set(METRICS_CACHE_KEY, JSON.stringify(metrics))
    },
  }
}

export function createRedisClient(connectionString: string): RedisLike {
  return new Redis(connectionString)
}
