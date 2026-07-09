export const meta = {
  name: 'hello-lane',
  description: 'Feature #130 WI-6 runtime proof: trivial named workflow — one agent returns a structured token',
  phases: [{ title: 'Probe' }],
}

// The proof: a named script under .claude/workflows/ can spawn one agent and
// return its structured output. No repo writes, no side effects.
phase('Probe')
const out = await agent(
  'Return exactly the JSON {"hello":"lane","probe":"wi-6"} as your structured output. Do nothing else — no tools.',
  { label: 'hello', schema: { type: 'object', required: ['hello', 'probe'],
      properties: { hello: { type: 'string' }, probe: { type: 'string' } } }, effort: 'low' }
)
return { proof: out && out.hello === 'lane' ? 'PASS' : 'FAIL', out }
