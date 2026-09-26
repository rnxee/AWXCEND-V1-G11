// The game's calendar day, in one fixed timezone.
//
// "First log of the day" and the streak both need a day boundary, and it has
// to be the same one everywhere: the database (compute_streak, via
// game_config streak_rules.timezone), these functions, and the browser
// (src/lib/streak.js). Before this, daily gold used UTC midnight while the
// browser's streak used the device's local day, so a user in GMT+8 could see
// a new day start eight hours before the server agreed.
export const GAME_TIMEZONE = 'Asia/Manila'

const dayFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: GAME_TIMEZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit'
})

/** 'YYYY-MM-DD' for an instant, in the game's timezone. */
export function gameDay(date: Date = new Date()): string {
  return dayFormatter.format(date)
}

/**
 * The natural key for a once-per-day gold award. Passed to award_gold as its
 * idempotency key, where a unique index — not a read-then-write check — is
 * what makes a second award for the same day impossible.
 */
export function dailyGoldKey(reason: string, userId: string, date: Date = new Date()): string {
  return `${reason}:${userId}:${gameDay(date)}`
}
