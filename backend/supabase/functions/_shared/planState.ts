// Small pure helpers about a stored plan, shared by the training-plan
// function and tested by src/lib/planState.test.js. Dates are YYYY-MM-DD
// game days (Asia/Manila), so plain string comparison orders them.

// "Plan next month" is offered from this many days before the plan ends.
export const NEXT_MONTH_WINDOW_DAYS = 3

type PlanDay = { day: string; session_key: string | null; status: string }

/** Share of training days already due (up to and including today) that were done. */
export function completionRate(days: PlanDay[], today: string): number {
  const due = days.filter(d => d.session_key && d.day <= today)
  if (due.length === 0) return 0
  return due.filter(d => d.status === 'done').length / due.length
}

function daysBetween(from: string, to: string): number {
  const ms = (s: string) => { const [y, m, d] = s.split('-').map(Number); return Date.UTC(y, m - 1, d) }
  return Math.round((ms(to) - ms(from)) / 86_400_000)
}

/** Whether to offer "Plan next month": the last few days, or any time after it ended. */
export function nextMonthAvailable(endDate: string, today: string): boolean {
  return daysBetween(today, endDate) <= NEXT_MONTH_WINDOW_DAYS
}

export function ratingCounts(ratings: { rating: string }[]) {
  const counts = { too_easy: 0, just_right: 0, too_hard: 0 } as Record<string, number>
  for (const r of ratings) if (r.rating in counts) counts[r.rating]++
  return counts
}
