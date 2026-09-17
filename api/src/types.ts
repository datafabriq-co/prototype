export interface OrderLineItem {
  orderDate: string
  orderId: string
  item: string
  quantity: number
  itemPrice: number
}

export interface FulfillmentRecord {
  fulfillmentDate: string
  orderId: string
  shippingCost: number
}

export interface DailyMetrics {
  revenue: number
  cogs: number
  net: number
}

export type MetricsByDate = Record<string, DailyMetrics>
