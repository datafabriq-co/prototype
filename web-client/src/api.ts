import type { MetricsByDate } from './types'

export async function fetchMetrics(): Promise<MetricsByDate> {
  const response = await fetch('/api/metrics')
  if (!response.ok) {
    throw new Error(`Failed to load metrics (status ${response.status})`)
  }
  return response.json() as Promise<MetricsByDate>
}
