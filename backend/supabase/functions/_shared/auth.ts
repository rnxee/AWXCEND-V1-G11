import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export async function getVerifiedUser(req: Request) {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return { user: null, error: 'Missing Authorization header' }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? Deno.env.get('PROJECT_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('PROJECT_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )

  const { data, error } = await supabase.auth.getUser()
  if (error || !data.user) return { user: null, error: 'Invalid or expired token' }

  return { user: data.user, error: null }
}
