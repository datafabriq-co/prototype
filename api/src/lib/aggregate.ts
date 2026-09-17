import type {
  OrderLineItem,
  FulfillmentRecord,
  DailyMetrics,
  MetricsByDate,
} from '../types.js'

function parseCsvLines(csvText: string): string[][] {
  return csvText
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line) => line.split(','))
}

export function parseOrdersCsv(csvText: string): OrderLineItem[] {
  const [, ...rows] = parseCsvLines(csvText)
  const result: OrderLineItem[] = []
  for (const row of rows) {
    const [orderDate, orderId, item, quantityStr, itemPriceStr] = row
    const quantity = Number(quantityStr)
    const itemPrice = Number(itemPriceStr)
    if (
      !orderDate ||
      !orderId ||
      !item ||
      !Number.isFinite(quantity) ||
      !Number.isFinite(itemPrice)
    ) {
      console.warn(`Skipping malformed orders.csv row: ${row.join(',')}`)
      continue
    }
    result.push({ orderDate, orderId, item, quantity, itemPrice })
  }
  return result
}

export function parseFulfillmentCsv(csvText: string): FulfillmentRecord[] {
  const [, ...rows] = parseCsvLines(csvText)
  const result: FulfillmentRecord[] = []
  for (const row of rows) {
    const [fulfillmentDate, orderId, shippingCostStr] = row
    const shippingCost = Number(shippingCostStr)
    if (!fulfillmentDate || !orderId || !Number.isFinite(shippingCost)) {
      console.warn(`Skipping malformed fulfillment.csv row: ${row.join(',')}`)
      continue
    }
    result.push({ fulfillmentDate, orderId, shippingCost })
  }
  return result
}

function round2(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100
}

function toCalendarDate(isoTimestamp: string): string {
  return isoTimestamp.slice(0, 10)
}

function lastNCalendarDays(endDay: string, n: number): string[] {
  const end = new Date(`${endDay}T00:00:00Z`)
  const days: string[] = []
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(end)
    d.setUTCDate(d.getUTCDate() - i)
    days.push(d.toISOString().slice(0, 10))
  }
  return days
}

export function computeDailyMetrics(
  orderLines: OrderLineItem[],
  fulfillments: FulfillmentRecord[],
  daysToInclude: number,
): MetricsByDate {
  const shippingCostByOrderId = new Map<string, number>()
  for (const record of fulfillments) {
    shippingCostByOrderId.set(record.orderId, record.shippingCost)
  }

  const revenueByOrderId = new Map<string, number>()
  const orderDateByOrderId = new Map<string, string>()
  for (const line of orderLines) {
    const lineRevenue = line.quantity * line.itemPrice
    revenueByOrderId.set(
      line.orderId,
      (revenueByOrderId.get(line.orderId) ?? 0) + lineRevenue,
    )
    orderDateByOrderId.set(line.orderId, line.orderDate)
  }

  const totalsByDay = new Map<string, { revenue: number; cogs: number }>()
  let latestDay: string | null = null
  for (const [orderId, revenue] of revenueByOrderId) {
    const orderDate = orderDateByOrderId.get(orderId)!
    const day = toCalendarDate(orderDate)
    const cogs = shippingCostByOrderId.get(orderId) ?? 0
    const existing = totalsByDay.get(day) ?? { revenue: 0, cogs: 0 }
    existing.revenue += revenue
    existing.cogs += cogs
    totalsByDay.set(day, existing)
    if (latestDay === null || day > latestDay) {
      latestDay = day
    }
  }

  const result: MetricsByDate = {}
  if (latestDay === null) {
    return result
  }

  for (const day of lastNCalendarDays(latestDay, daysToInclude)) {
    const dayTotals = totalsByDay.get(day) ?? { revenue: 0, cogs: 0 }
    const metrics: DailyMetrics = {
      revenue: round2(dayTotals.revenue),
      cogs: round2(dayTotals.cogs),
      net: round2(dayTotals.revenue - dayTotals.cogs),
    }
    result[day] = metrics
  }
  return result
}
