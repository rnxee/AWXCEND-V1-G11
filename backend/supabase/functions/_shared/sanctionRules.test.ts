// node --test backend/supabase/functions/_shared/sanctionRules.test.ts   (Node 23.6+ runs TypeScript)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { canLift, canSanction, computeEndsAt, isPrivilege, sanctionMessage } from './sanctionRules.ts'

const NOW = new Date('2026-01-31T04:00:00Z')

test('end times: units, month-end clamping, until, permanent and bad input', () => {
  const at = (d: object) => {
    const r = computeEndsAt(d, NOW)
    assert.ok(r.ok, JSON.stringify(r))
    return r.ok && r.endsAt ? r.endsAt.toISOString() : null
  }
  assert.equal(at({ amount: 3, unit: 'hours' }), '2026-01-31T07:00:00.000Z')
  assert.equal(at({ amount: 1, unit: 'weeks' }), '2026-02-07T04:00:00.000Z')
  assert.equal(at({ amount: 1, unit: 'months' }), '2026-02-28T04:00:00.000Z')  // 31 Jan + 1 month
  assert.equal(at({ amount: 1, unit: 'years' }), '2027-01-31T04:00:00.000Z')
  assert.equal(at({ permanent: true }), null)
  assert.equal(at({ until: '2026-03-01T00:00:00Z' }), '2026-03-01T00:00:00.000Z')
  assert.equal(at({ amount: 999, unit: 'years' }), '2126-01-31T04:00:00.000Z')  // capped at 100 years
  for (const bad of [{ amount: 0, unit: 'days' }, { amount: 2, unit: 'fortnights' }, { until: '2020-01-01' }, {}]) {
    assert.equal(computeEndsAt(bad, NOW).ok, false, JSON.stringify(bad))
  }
})

test('who may sanction and lift', () => {
  const mod = { id: 'm', role: 'moderator' }, admin = { id: 'a', role: 'admin' }
  assert.equal(canSanction(mod, { id: 'p', role: 'user' }), null)
  assert.match(canSanction(mod, { id: 'm2', role: 'moderator' })!, /Only an admin/)
  assert.equal(canSanction(admin, { id: 'm2', role: 'moderator' }), null)
  assert.match(canSanction(admin, { id: 'a2', role: 'admin' })!, /Admins can't/)
  assert.match(canSanction(mod, mod)!, /yourself/)
  assert.match(canSanction({ id: 'u', role: 'user' }, { id: 'p', role: 'user' })!, /Moderator access/)
  assert.match(canLift('moderator', 'admin')!, /Only an admin/)
  assert.equal(canLift('moderator', 'moderator'), null)
  assert.equal(canLift('admin', 'admin'), null)
})

test('what the player reads', () => {
  const ban = sanctionMessage({ kind: 'ban', privileges: [], reason: 'Spam', ends_at: null })
  assert.equal(ban, 'Account suspended permanently. Reason: Spam')
  const r = sanctionMessage({ kind: 'restrict', privileges: ['chat', 'dm'], reason: 'Insults', ends_at: '2026-02-01T04:00:00Z' })
  assert.match(r, /^You can't use community chat, direct messages until Feb 1, 2026.*12:00\s?PM\. Reason: Insults$/)
  assert.equal(isPrivilege('chat'), true)
  assert.equal(isPrivilege('domain'), false)
})
