import { app, InvocationContext } from '@azure/functions'
import { readBlobText } from '../lib/blobSource.js'
import { parseOrdersCsv, parseFulfillmentCsv, computeDailyMetrics } from '../lib/aggregate.js'
import { createMetricsStore, createRedisClient } from '../lib/redisStore.js'
import type { MetricsStore } from '../lib/redisStore.js'
import type { MetricsByDate } from '../types.js'
import {
  DASHBOARD_WINDOW_DAYS,
  CSV_CONTAINER_NAME,
  ORDERS_BLOB_NAME,
  FULFILLMENT_BLOB_NAME,
} from '../constants.js'

export async function runPreprocessing(
  ordersCsvText: string,
  fulfillmentCsvText: string,
  store: MetricsStore,
): Promise<MetricsByDate> {
  const orderLines = parseOrdersCsv(ordersCsvText)
  const fulfillments = parseFulfillmentCsv(fulfillmentCsvText)
  const metrics = computeDailyMetrics(orderLines, fulfillments, DASHBOARD_WINDOW_DAYS)
  await store.set(metrics)
  return metrics
}

app.storageBlob('preprocessMetrics', {
  path: `${CSV_CONTAINER_NAME}/{name}`,
  connection: 'CSV_STORAGE_CONNECTION',
  handler: async (_blob: unknown, context: InvocationContext) => {
    const storageConnection = process.env.CSV_STORAGE_CONNECTION!
    const redisConnection = process.env.REDIS_CONNECTION_STRING!
    const [ordersCsvText, fulfillmentCsvText] = await Promise.all([
      readBlobText(storageConnection, CSV_CONTAINER_NAME, ORDERS_BLOB_NAME),
      readBlobText(storageConnection, CSV_CONTAINER_NAME, FULFILLMENT_BLOB_NAME),
    ])
    const store = createMetricsStore(createRedisClient(redisConnection))
    const metrics = await runPreprocessing(ordersCsvText, fulfillmentCsvText, store)
    context.log(`Processed metrics for ${Object.keys(metrics).length} day(s)`)
  },
})
