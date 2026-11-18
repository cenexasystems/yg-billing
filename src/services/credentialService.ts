import { supabase, isSupabaseConfigured } from '../lib/supabase'

export type CredentialRoleKey = 'admin' | 'pos1_staff' | 'pos2_staff' | 'pos3_staff'

/** DB-stored password overrides, keyed by role. A missing/empty entry
 * means "use the .env default" for that account. */
export async function fetchCredentialOverrides(): Promise<Partial<Record<CredentialRoleKey, string>>> {
  if (!isSupabaseConfigured) return {}
  const { data, error } = await supabase.from('portal_credentials').select('role_key, password_override')
  if (error || !data) return {}
  const overrides: Partial<Record<CredentialRoleKey, string>> = {}
  data.forEach((row) => {
    const value = String(row.password_override || '').trim()
    if (value) overrides[row.role_key as CredentialRoleKey] = value
  })
  return overrides
}

export async function updateCredentialPassword(roleKey: CredentialRoleKey, newPassword: string): Promise<void> {
  const trimmed = newPassword.trim()
  if (trimmed.length < 4) {
    throw new Error('Password must be at least 4 characters')
  }
  const { error } = await supabase
    .from('portal_credentials')
    .upsert({ role_key: roleKey, password_override: trimmed, updated_at: new Date().toISOString() }, { onConflict: 'role_key' })
  if (error) throw error
}
