// The exercises a monthly training plan can use, with OUR OWN planning
// metadata. Pure, so src/lib/planGenerator.test.js can import it directly.
//
// Every name here must exist in public.exercises (log_workout_and_progress
// validates it) and be rep- or duration-typed: a plan day is run through the
// routine runner, which logs via /log-workout. Distance work (jogging,
// walking, rucking) belongs to the GPS tracker and is left out.
//
// `repdb` is the matching exercise id in the RepDB dataset
// (github.com/RepDB/exercise-dataset). This file holds only the id — no RepDB
// text. RepDB's own fields (muscles, difficulty, safety tags, instructions,
// images) are imported into public.exercise_library by
// scripts/import-repdb.mjs and read from there at plan time.
//
// slot: the movement a plan fills.
//   squat · hinge · lunge   — lower body
//   push_h · push_v         — horizontal / vertical press
//   pull_v · pull_h         — vertical / horizontal pull
//   arms · shoulders        — accessory isolation
//   core · conditioning     — trunk work and heart-rate work
//   carry · olympic         — specialist lifts (their paths only)
// equipment: the least a user needs — 'none' (bodyweight), 'dumbbell'
//   (home dumbbells, a bench counts as home), or 'gym' (barbell, cable,
//   machine, bar, specialist implements).
// role: 'main' lifts open a session and get the progression; 'accessory'
//   fills the rest.
// easier / harder: the swap used when a session's difficulty level reaches
//   its limit (same slot, one step down / up).

export type Slot =
  | 'squat' | 'hinge' | 'lunge' | 'push_h' | 'push_v' | 'pull_v' | 'pull_h'
  | 'arms' | 'shoulders' | 'core' | 'conditioning' | 'carry' | 'olympic'
export type EquipmentLevel = 'none' | 'dumbbell' | 'gym'

export type CatalogEntry = {
  name: string
  label: string
  metric: 'reps' | 'duration'
  slot: Slot
  equipment: EquipmentLevel
  role: 'main' | 'accessory'
  repdb: string | null
  easier?: string
  harder?: string
  // Specialist implements (atlas stone, yoke) or technical lifts (snatch,
  // clean & jerk): only planned for the paths built around them.
  specialistFor?: string[]
}

export const PLAN_CATALOG: CatalogEntry[] = [
  // Lower body
  { name: 'squat', label: 'Squat', metric: 'reps', slot: 'squat', equipment: 'gym', role: 'main', repdb: 'squat', easier: 'lunges' },
  { name: 'bulgariansplitsquat', label: 'Bulgarian Split Squat', metric: 'reps', slot: 'lunge', equipment: 'dumbbell', role: 'main', repdb: 'bulgarian-split-squat', easier: 'lunges', harder: 'squat' },
  { name: 'lunges', label: 'Lunges', metric: 'reps', slot: 'lunge', equipment: 'none', role: 'main', repdb: 'lunge', easier: 'wallsit', harder: 'bulgariansplitsquat' },
  { name: 'wallsit', label: 'Wall Sit', metric: 'duration', slot: 'squat', equipment: 'none', role: 'accessory', repdb: 'wall-sit', harder: 'lunges' },
  { name: 'legextension', label: 'Leg Extension', metric: 'reps', slot: 'squat', equipment: 'gym', role: 'accessory', repdb: 'leg-extension' },
  { name: 'deadlift', label: 'Deadlift', metric: 'reps', slot: 'hinge', equipment: 'gym', role: 'main', repdb: 'deadlift', easier: 'romaniandeadlift' },
  { name: 'romaniandeadlift', label: 'Romanian Deadlift', metric: 'reps', slot: 'hinge', equipment: 'dumbbell', role: 'main', repdb: 'dumbbell-romanian-deadlift', easier: 'hipthrust', harder: 'deadlift' },
  { name: 'hipthrust', label: 'Hip Thrust', metric: 'reps', slot: 'hinge', equipment: 'dumbbell', role: 'accessory', repdb: 'dumbbell-hip-thrust', harder: 'romaniandeadlift' },

  // Push
  { name: 'benchpress', label: 'Bench Press', metric: 'reps', slot: 'push_h', equipment: 'gym', role: 'main', repdb: 'bench-press', easier: 'pushup' },
  { name: 'inclinebenchpress', label: 'Incline Bench Press', metric: 'reps', slot: 'push_h', equipment: 'gym', role: 'accessory', repdb: 'incline-bench-press' },
  { name: 'declinebenchpress', label: 'Decline Bench Press', metric: 'reps', slot: 'push_h', equipment: 'gym', role: 'accessory', repdb: 'decline-bench-press-barbell' },
  { name: 'pushup', label: 'Push Up', metric: 'reps', slot: 'push_h', equipment: 'none', role: 'main', repdb: 'push-up', harder: 'tricepdips' },
  { name: 'chestflymachine', label: 'Chest Fly Machine', metric: 'reps', slot: 'push_h', equipment: 'gym', role: 'accessory', repdb: 'machine-chest-fly' },
  { name: 'shoulderpress', label: 'Shoulder Press', metric: 'reps', slot: 'push_v', equipment: 'dumbbell', role: 'main', repdb: 'dumbbell-shoulder-press', easier: 'lateralraise' },
  { name: 'tricepdips', label: 'Tricep Dips', metric: 'reps', slot: 'arms', equipment: 'none', role: 'accessory', repdb: 'bench-dips', easier: 'pushup' },
  { name: 'triceppushdown', label: 'Tricep Pushdown', metric: 'reps', slot: 'arms', equipment: 'gym', role: 'accessory', repdb: 'tricep-pushdown' },

  // Pull
  { name: 'pullup', label: 'Pull Up', metric: 'reps', slot: 'pull_v', equipment: 'gym', role: 'main', repdb: 'pull-up', easier: 'latpulldown' },
  { name: 'latpulldown', label: 'Lat Pulldown', metric: 'reps', slot: 'pull_v', equipment: 'gym', role: 'main', repdb: 'lat-pulldown', harder: 'pullup' },
  { name: 'tbarrow', label: 'T-Bar Row', metric: 'reps', slot: 'pull_h', equipment: 'gym', role: 'main', repdb: 't-bar-row' },
  { name: 'barbellbicepscurl', label: 'Barbell Bicep Curl', metric: 'reps', slot: 'arms', equipment: 'gym', role: 'accessory', repdb: 'barbell-curl', easier: 'hammercurl' },
  { name: 'hammercurl', label: 'Hammer Curl', metric: 'reps', slot: 'arms', equipment: 'dumbbell', role: 'accessory', repdb: 'hammer-curl', harder: 'barbellbicepscurl' },

  // Shoulders
  { name: 'lateralraise', label: 'Lateral Raise', metric: 'reps', slot: 'shoulders', equipment: 'dumbbell', role: 'accessory', repdb: 'lateral-raise', harder: 'shoulderpress' },

  // Core
  { name: 'plank', label: 'Plank', metric: 'duration', slot: 'core', equipment: 'none', role: 'accessory', repdb: 'plank', harder: 'sideplank' },
  { name: 'sideplank', label: 'Side Plank', metric: 'duration', slot: 'core', equipment: 'none', role: 'accessory', repdb: 'side-plank', easier: 'plank' },
  { name: 'legraises', label: 'Leg Raises', metric: 'reps', slot: 'core', equipment: 'none', role: 'accessory', repdb: 'lying-leg-raise' },
  { name: 'russiantwist', label: 'Russian Twist', metric: 'reps', slot: 'core', equipment: 'none', role: 'accessory', repdb: 'russian-twist' },

  // Conditioning
  { name: 'jumpingjacks', label: 'Jumping Jacks', metric: 'reps', slot: 'conditioning', equipment: 'none', role: 'accessory', repdb: 'jumping-jacks', harder: 'burpee' },
  { name: 'mountainclimbers', label: 'Mountain Climbers', metric: 'reps', slot: 'conditioning', equipment: 'none', role: 'accessory', repdb: 'mountain-climbers', harder: 'burpee' },
  { name: 'burpee', label: 'Burpee', metric: 'reps', slot: 'conditioning', equipment: 'none', role: 'accessory', repdb: 'burpees', easier: 'mountainclimbers' },
  { name: 'shadowboxing', label: 'Shadow Boxing', metric: 'duration', slot: 'conditioning', equipment: 'none', role: 'accessory', repdb: null },
  { name: 'cycling', label: 'Cycling', metric: 'duration', slot: 'conditioning', equipment: 'gym', role: 'accessory', repdb: 'stationary-bike' },

  // Specialist lifts and carries — only for the paths built around them.
  { name: 'farmerscarry', label: "Farmer's Carry", metric: 'reps', slot: 'carry', equipment: 'dumbbell', role: 'accessory', repdb: 'dumbbell-farmers-walk', specialistFor: ['strongman', 'tactical'] },
  { name: 'yokewalk', label: 'Yoke Walk', metric: 'reps', slot: 'carry', equipment: 'gym', role: 'main', repdb: null, specialistFor: ['strongman'] },
  { name: 'atlasstone', label: 'Atlas Stone', metric: 'reps', slot: 'carry', equipment: 'gym', role: 'main', repdb: null, specialistFor: ['strongman'] },
  { name: 'powerclean', label: 'Power Clean', metric: 'reps', slot: 'olympic', equipment: 'gym', role: 'main', repdb: 'hang-power-clean', specialistFor: ['weightlifter', 'strongman'] },
  { name: 'cleanandjerk', label: 'Clean & Jerk', metric: 'reps', slot: 'olympic', equipment: 'gym', role: 'main', repdb: 'clean-and-jerk', specialistFor: ['weightlifter'] },
  { name: 'snatch', label: 'Snatch', metric: 'reps', slot: 'olympic', equipment: 'gym', role: 'main', repdb: 'snatch', specialistFor: ['weightlifter'] }
]

export const CATALOG_BY_NAME: Record<string, CatalogEntry> =
  Object.fromEntries(PLAN_CATALOG.map(e => [e.name, e]))

// Equipment a user has, from the survey → which equipment levels they can use.
export const EQUIPMENT_ACCESS: Record<string, EquipmentLevel[]> = {
  bodyweight: ['none'],
  dumbbells: ['none', 'dumbbell'],
  gym: ['none', 'dumbbell', 'gym']
}

// "Areas to go easy on" → the RepDB tag that marks an exercise as safe for
// it. RepDB has no wrist tag, so wrists are not offered.
export const AREA_SAFE_TAG: Record<string, string> = {
  knees: 'knee_safe',
  lower_back: 'lower_back_safe',
  shoulders: 'shoulder_safe'
}
