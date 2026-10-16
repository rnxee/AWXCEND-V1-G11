import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cleanText, wordCount } from './validation.ts'

const u = (...cps: number[]) => String.fromCodePoint(...cps)  // keeps invisible characters visible in this file
const ZWSP = u(0x200b), RLO = u(0x202e), NUL = u(0), ZWJ = u(0x200d)

test('cleanText drops invisible and direction characters, keeps real text', () => {
  assert.equal(cleanText(`  hi${ZWSP}there${RLO}gnp.exe${NUL} `), 'hitheregnp.exe')
  assert.equal(cleanText('line 1\nline 2\ttab'), 'line 1\nline 2\ttab')
  const family = u(0x1f468) + ZWJ + u(0x1f469) + ZWJ + u(0x1f467)
  const keycap = '1' + u(0xfe0f, 0x20e3)
  assert.equal(cleanText(`${family} Pho${u(0x31b, 0x309)} ${keycap}`), `${family} Ph${u(0x1edf)} ${keycap}`)
  // zalgo: NFC folds the first mark into the letter, two more stay, the rest go
  assert.equal(cleanText('Z' + u(0x301, 0x302, 0x303, 0x304, 0x305)), u(0x179, 0x302, 0x303))
  assert.equal(cleanText(42), '')
})

test('wordCount', () => {
  assert.equal(wordCount('  one two\nthree  '), 3)
  assert.equal(wordCount(''), 0)
})
