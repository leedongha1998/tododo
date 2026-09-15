// 호출자 확인과 service 클라이언트.
//
// 클라이언트가 보낸 user id를 믿지 않는다. Authorization 헤더의 JWT로 확인한 id만 DB 함수에 넘긴다.
// service 전용 DB 함수는 service_role 키로만 부른다(앱에는 EXECUTE 권한이 없다).

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

/// JWT로 확인한 호출자 id. 없거나 틀리면 null.
export async function getUserId(req: Request): Promise<string | null> {
  const authorization = req.headers.get('Authorization');
  if (!authorization) return null;

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}

export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
}
