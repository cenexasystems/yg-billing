import { isSupabaseConfigured, supabase } from '../lib/supabase'
import { formatCurrency } from '../lib/retail'
import type { PosBranch } from '../store/store'

const COUPON_COLUMNS = 'id, code, percentage, is_active, expiry_date, usage_limit, usage_count, min_order_value'

export type AppliedCoupon = {
  code: string
  percentage: number
  discount: number
  minOrderValue: number
}

/**
 * A coupon is valid through the END of its expiry date in local time.
 * (`new Date('2026-09-30')` is UTC midnight, which in India would expire it at 05:30 on the 30th.)
 */
export function isCouponExpired(expiry: string | null | undefined, now: Date = new Date()): boolean {
  if (!expiry) return false
  // A date saved into the timestamp column comes back as UTC midnight ("2026-10-30T00:00:00+00:00"); treat it as that date.
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ]00:00:00(?:\.0+)?(?:Z|[+-]00(?::?00)?)?)?$/.exec(String(expiry).trim())
  const end = m
    ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 23, 59, 59, 999)
    : new Date(expiry)
  return !Number.isNaN(end.getTime()) && end < now
}

export async function validateCoupon(
  rawCode: string,
  subtotal: number,
  branch: PosBranch = 'pos1',
): Promise<{ data: AppliedCoupon | null; error: string | null }> {
  const code = rawCode.trim().toUpperCase()

  if (!isSupabaseConfigured) {
    return { data: null, error: 'Coupon validation requires a live connection' }
  }

  try {
    const { data, error: dbErr } = await supabase
      .from('coupons')
      .select(COUPON_COLUMNS)
      .eq('is_active', true)
      .eq('branch', branch)
      .ilike('code', code)
      .single()

    if (dbErr || !data) return { data: null, error: 'Invalid or expired coupon code' }

    if (isCouponExpired(data.expiry_date)) {
      return { data: null, error: 'This coupon has expired' }
    }

    const usageLimit = Number(data.usage_limit || 0)
    const usageCount = Number(data.usage_count || 0)
    if (usageLimit > 0 && usageCount >= usageLimit) {
      return { data: null, error: 'Coupon usage limit has been reached' }
    }

    if (data.min_order_value && subtotal < Number(data.min_order_value)) {
      return {
        data: null,
        error: `Minimum order of ${formatCurrency(Number(data.min_order_value))} required`,
      }
    }

    const discount = Math.round((subtotal * Number(data.percentage) / 100) * 100) / 100
    return {
      data: { code: String(data.code), percentage: Number(data.percentage), discount, minOrderValue: Number(data.min_order_value || 0) },
      error: null,
    }
  } catch {
    return { data: null, error: 'Failed to validate coupon. Try again.' }
  }
}
