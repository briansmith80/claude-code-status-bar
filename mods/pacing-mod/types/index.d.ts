export type Limit = { kind: string; percentUsed: number; resetsAt?: string }
export type Sess = { startedAt: number | null; usd: number | null }
export type Ctx = {
  percent: number | null
  tokens: number | null
  window: number
  compactAt: number | null
  autoCompact: boolean
  model: string | null
}

declare module 'claude-code' {
  interface PluginState {
    'pacing-mod': {
      limits: Shaped<Limit[]>
      context: Shaped<Ctx>
      session: Shaped<Sess>
      toasted: Shaped<string[]>
      isClosed: boolean
      reopenRow: string
    }
  }
}
