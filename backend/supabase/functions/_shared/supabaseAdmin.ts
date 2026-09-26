import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export function getAdminClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? Deno.env.get('PROJECT_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('PROJECT_SERVICE_ROLE_KEY')!
  )
}
