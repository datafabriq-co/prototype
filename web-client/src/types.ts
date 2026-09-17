export interface DailyMetrics {
  revenue: number
  cogs: number
  net: number
}

export type MetricsByDate = Record<string, DailyMetrics>
