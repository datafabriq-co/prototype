import MetricsTable from './MetricsTable'

function App() {
  return (
    <div className="min-h-screen bg-slate-50 p-8">
      <h1 className="mb-4 text-2xl font-bold text-slate-800">
        Daily Revenue, COGS &amp; Net
      </h1>
      <MetricsTable />
    </div>
  )
}

export default App
