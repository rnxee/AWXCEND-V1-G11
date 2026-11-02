export const MAX_COMMENT_LENGTH = 1000
export const REACTIONS = ['like', 'love', 'fire', 'strong'] as const
export type Reaction = typeof REACTIONS[number]

export function checkComment(raw: unknown): { text: string; error: string | null } {
  const text = typeof raw === 'string' ? raw.trim() : ''
  if (!text) return { text, error: 'Comment is required' }
  if (text.length > MAX_COMMENT_LENGTH) return { text, error: `Comment must be ${MAX_COMMENT_LENGTH} characters or fewer` }
  return { text, error: null }
}

export function isReaction(raw: unknown): raw is Reaction {
  return typeof raw === 'string' && (REACTIONS as readonly string[]).includes(raw)
}
