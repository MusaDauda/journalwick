import { z } from 'zod'

const livenessSchema = z
  .object({
    status: z.literal('alive'),
    service: z.literal('journalwick'),
  })
  .strict()

export type Liveness = z.infer<typeof livenessSchema>

export async function fetchLiveness(): Promise<Liveness> {
  const response = await fetch('/api/v1/health/live', {
    method: 'GET',
    headers: { Accept: 'application/json' },
    credentials: 'same-origin',
    cache: 'no-store',
  })

  if (!response.ok) {
    throw new Error('The API did not return a successful liveness response.')
  }

  return livenessSchema.parse(await response.json())
}
