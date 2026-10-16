import { test } from 'node:test'
import assert from 'node:assert/strict'
import { canEdit, checkMessage } from './messageRules.ts'

test('edits are allowed for 15 minutes, with or without a time zone on the stored time', () => {
  const now = Date.parse('2026-10-16T12:00:00Z')
  assert.equal(canEdit('2026-10-16T11:50:00.123', now), true)        // naive UTC (chat_messages)
  assert.equal(canEdit('2026-10-16T11:50:00+00:00', now), true)      // with zone (direct_messages)
  assert.equal(canEdit('2026-10-16T11:40:00', now), false)
  assert.equal(canEdit('2026-10-16T19:50:00+08:00', now), true)      // same instant as 11:50 UTC
  assert.equal(canEdit('garbage', now), false)
})

test('message text rules', () => {
  assert.equal(checkMessage('  hi  ', 500).text, 'hi')
  assert.equal(checkMessage('   ', 500).error, 'message is required')
  assert.match(checkMessage('x'.repeat(501), 500).error!, /500 characters/)
  assert.match(checkMessage(Array(101).fill('a').join(' '), 2000).error!, /100 words/)
  assert.equal(checkMessage(Array(100).fill('a').join(' '), 2000).error, null)
})
