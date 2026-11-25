// 호출자 확인과 service 클라이언트.
//
// 클라이언트가 보낸 user id를 믿지 않는다. Authorization 헤더의 JWT로 확인한 id만 DB 함수에 넘긴다.
// service 전용 DB 함수는 service_role 키로만 부른다(앱에는 EXECUTE 권한이 없다).

import { createClient, SupabaseClient, type User } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

/// JWT로 확인한 호출자 id. 없거나 틀리면 null.
export async function getUserId(req: Request): Promise<string | null> {
  return (await getUser(req))?.id ?? null;
}

/// JWT로 확인한 호출자의 **사용자 레코드 전체**(identities·app_metadata 포함). 없거나 틀리면 null.
/// delete-account가 탈퇴 **전에** 카카오 회원번호를 읽는 데 쓴다 — delete_account가 auth.users를
/// 지우면 auth.identities도 함께 사라진다(kakao-login design §4.2).
export async function getUser(req: Request): Promise<User | null> {
  const authorization = req.headers.get('Authorization');
  if (!authorization) return null;

  const client = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}

export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
}

/// 호출자의 JWT 그대로 DB를 부르는 클라이언트. `auth.uid()`가 호출자가 되어야 하는 RPC
/// (예: delete_account)를 Edge에서 대신 부를 때 쓴다 — service 롤로 부르면 uid가 null이다.
export function userClient(authorization: string): SupabaseClient {
  return createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
}
