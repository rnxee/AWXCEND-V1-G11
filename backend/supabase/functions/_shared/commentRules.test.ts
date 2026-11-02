import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checkComment, isReaction, MAX_COMMENT_LENGTH } from './commentRules.ts'

test('comment text is trimmed and bounded', () => {
  assert.deepEqual(checkComment('  helpful note  '), { text: 'helpful note', error: null })
  assert.equal(checkComment(' ').error, 'Comment is required')
  assert.match(checkComment('x'.repeat(MAX_COMMENT_LENGTH + 1)).error!, /1000 characters/)
})

test('reaction values are an explicit allow-list', () => {
  assert.equal(isReaction('fire'), true)
  assert.equal(isReaction('thumbs_up'), false)
  assert.equal(isReaction(null), false)
})
