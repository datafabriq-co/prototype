import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions'
import { createMetricsStore, createRedisClient } from '../lib/redisStore.js'
import type { MetricsStore } from '../lib/redisStore.js'

export async function handleGetMetrics(store: MetricsStore): Promise<HttpResponseInit> {
  const metrics = await store.get()
  if (metrics === null) {
    return {
      status: 503,
      jsonBody: { error: 'metrics not yet available' },
    }
  }
  return {
    status: 200,
    jsonBody: metrics,
  }
}

app.http('getMetrics', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'metrics',
  handler: async (_request: HttpRequest, _context: InvocationContext) => {
    const redisConnection = process.env.REDIS_CONNECTION_STRING!
    const store = createMetricsStore(createRedisClient(redisConnection))
    return handleGetMetrics(store)
  },
})
