import { useEffect, useState } from 'react'
import { fetchMetrics } from './api'
import type { MetricsByDate } from './types'

const currencyFormatter = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
})

type LoadState =
  | { status: 'loading' }
  | { status: 'error'; message: string }
  | { status: 'ready'; metrics: MetricsByDate }

function MetricsTable() {
  const [state, setState] = useState<LoadState>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    fetchMetrics()
      .then((metrics) => {
        if (!cancelled) setState({ status: 'ready', metrics })
      })
      .catch((error: Error) => {
        if (!cancelled) setState({ status: 'error', message: error.message })
      })
    return () => {
      cancelled = true
    }
  }, [])

  if (state.status === 'loading') {
    return <p role="status">Loading metrics…</p>
  }

  if (state.status === 'error') {
    return <p role="alert">{state.message}</p>
  }

  const dates = Object.keys(state.metrics).sort()

  return (
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Revenue</th>
          <th>COGS</th>
          <th>Net</th>
        </tr>
      </thead>
      <tbody>
        {dates.map((date) => {
          const { revenue, cogs, net } = state.metrics[date]
          return (
            <tr key={date}>
              <td>{date}</td>
              <td>{currencyFormatter.format(revenue)}</td>
              <td>{currencyFormatter.format(cogs)}</td>
              <td>{currencyFormatter.format(net)}</td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

export default MetricsTable
