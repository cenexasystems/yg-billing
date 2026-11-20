import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { isSupabaseConfigured, supabase } from '../../lib/supabase'
import { formatCurrency } from '../../lib/retail'
import type { PosBranch } from '../../store/store'

/** A past customer of this POS, built from its bills and advance orders. */
export type CustomerSuggestion = {
  /** 10-digit mobile number */
  phone: string
  name: string
  address: string
  bills: number
  totalSpent: number
  lastDate: string
}

const PLACEHOLDER_NAMES = /^(walk-?in customer|walk-?in|customer|guest)$/i
const PLACEHOLDER_ADDRESSES = /^(pos counter|counter|-)$/i

/** Last 10 digits of a stored phone (stored as 91XXXXXXXXXX). */
const tenDigits = (value: unknown): string => {
  const digits = String(value ?? '').replace(/\D/g, '')
  return digits.length > 10 ? digits.slice(-10) : digits
}

/** Digits the user typed, without a leading +91 / 91 / 0 country or trunk prefix. */
const typedDigits = (value: string): string => {
  let digits = value.replace(/\D/g, '')
  if (digits.length > 10 && digits.startsWith('91')) digits = digits.slice(2)
  if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1)
  return digits
}

type Row = { customer_name?: string | null; phone?: string | null; address?: string | null; created_at?: string | null; total?: number | string | null; total_amount?: number | string | null }

async function searchCustomers(branch: PosBranch, digits: string): Promise<CustomerSuggestion[]> {
  const pattern = `%${digits}%`
  const [orders, advances] = await Promise.all([
    supabase
      .from('orders')
      .select('customer_name, phone, address, created_at, total')
      .eq('branch', branch)
      .ilike('phone', pattern)
      .order('created_at', { ascending: false })
      .limit(200),
    supabase
      .from('advance_orders')
      .select('customer_name, phone, address, created_at, total_amount')
      .eq('branch', branch)
      .ilike('phone', pattern)
      .order('created_at', { ascending: false })
      .limit(100),
  ])
  const rows: Row[] = [...((orders.data as Row[]) || []), ...((advances.data as Row[]) || [])]
  rows.sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')))

  const byPhone = new Map<string, CustomerSuggestion>()
  for (const row of rows) {
    const phone = tenDigits(row.phone)
    if (phone.length !== 10 || !phone.includes(digits)) continue
    const name = String(row.customer_name || '').trim()
    const address = String(row.address || '').trim()
    const amount = Number(row.total ?? row.total_amount) || 0
    const found = byPhone.get(phone)
    if (!found) {
      byPhone.set(phone, {
        phone,
        name: PLACEHOLDER_NAMES.test(name) ? '' : name,
        address: PLACEHOLDER_ADDRESSES.test(address) ? '' : address,
        bills: 1,
        totalSpent: amount,
        lastDate: String(row.created_at || ''),
      })
      continue
    }
    // Rows are newest first: keep the latest real name / address, fill gaps from older bills
    found.bills += 1
    found.totalSpent += amount
    if (!found.name && name && !PLACEHOLDER_NAMES.test(name)) found.name = name
    if (!found.address && address && !PLACEHOLDER_ADDRESSES.test(address)) found.address = address
  }
  return [...byPhone.values()]
    .sort((a, b) => Number(b.phone.startsWith(digits)) - Number(a.phone.startsWith(digits)) || b.lastDate.localeCompare(a.lastDate))
    .slice(0, 8)
}

type Props = {
  branch: PosBranch
  value: string
  onChange: (value: string) => void
  /** Called when a past customer is picked from the dropdown */
  onSelect: (customer: CustomerSuggestion) => void
  className?: string
  placeholder?: string
  ariaLabel?: string
}

/**
 * Mobile number box for the POS bill. While typing (3+ digits) it lists past
 * customers of THIS POS only whose number matches, with their name, address and
 * bill history; picking one fills the customer details.
 */
export function CustomerPhoneInput({ branch, value, onChange, onSelect, className, placeholder, ariaLabel }: Props) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [open, setOpen] = useState(false)
  // Results are kept with the query they answer, so an older answer never shows for a newer number
  const [found, setFound] = useState<{ key: string; list: CustomerSuggestion[] }>({ key: '', list: [] })
  const [active, setActive] = useState(0)
  const [rect, setRect] = useState<{ left: number; top: number; width: number } | null>(null)
  const digits = typedDigits(value)
  const queryKey = `${branch}|${digits}`
  const canSearch = open && digits.length >= 3 && isSupabaseConfigured
  const results = found.key === queryKey ? found.list : []
  const loading = canSearch && found.key !== queryKey

  // Search as the number is typed (debounced); ignore answers for an older query
  useEffect(() => {
    if (!canSearch) return
    let cancelled = false
    const timer = window.setTimeout(() => {
      searchCustomers(branch, digits)
        .then((list) => { if (!cancelled) { setFound({ key: queryKey, list }); setActive(0) } })
        .catch(() => { if (!cancelled) setFound({ key: queryKey, list: [] }) })
    }, 250)
    return () => { cancelled = true; window.clearTimeout(timer) }
  }, [branch, digits, canSearch, queryKey])

  // The dropdown is portalled (bill panels clip overflow), so it follows the input's position
  useLayoutEffect(() => {
    if (!open) return
    const place = () => {
      const r = inputRef.current?.getBoundingClientRect()
      if (r) setRect({ left: r.left, top: r.bottom + 4, width: Math.max(r.width, 260) })
    }
    place()
    window.addEventListener('resize', place)
    window.addEventListener('scroll', place, true)
    return () => {
      window.removeEventListener('resize', place)
      window.removeEventListener('scroll', place, true)
    }
  }, [open])

  const pick = (c: CustomerSuggestion) => {
    onSelect(c)
    setOpen(false)
  }

  const showList = canSearch && (loading || results.length > 0) && rect

  return (
    <>
      <input
        ref={inputRef}
        type="text"
        inputMode="tel"
        autoComplete="off"
        value={value}
        onChange={(e) => { onChange(e.target.value); setOpen(true) }}
        onFocus={() => setOpen(true)}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (!showList || results.length === 0) return
          if (e.key === 'ArrowDown') { e.preventDefault(); setActive((i) => (i + 1) % results.length) }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((i) => (i - 1 + results.length) % results.length) }
          else if (e.key === 'Enter') { e.preventDefault(); pick(results[active]) }
          else if (e.key === 'Escape') setOpen(false)
        }}
        placeholder={placeholder}
        aria-label={ariaLabel}
        aria-autocomplete="list"
        aria-expanded={Boolean(showList)}
        className={className}
      />
      {showList && createPortal(
        <div
          role="listbox"
          style={{ position: 'fixed', left: Math.min(rect.left, window.innerWidth - rect.width - 8), top: rect.top, width: rect.width, zIndex: 1000 }}
          className="max-h-72 overflow-y-auto rounded-xl border border-gray-200 bg-white shadow-xl"
          onMouseDown={(e) => e.preventDefault()}
        >
          {loading && results.length === 0 ? (
            <p className="px-3 py-2.5 text-[12px] font-semibold text-gray-500">Searching customers…</p>
          ) : results.map((c, i) => (
            <button
              key={c.phone}
              type="button"
              role="option"
              aria-selected={i === active}
              onMouseEnter={() => setActive(i)}
              onClick={() => pick(c)}
              className={`block w-full text-left px-3 py-2 border-b border-gray-100 last:border-b-0 ${i === active ? 'bg-[#FFF9E6]' : 'bg-white'}`}
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-[13px] font-black text-[#111111] tabular-nums">{c.phone.slice(0, 5)} {c.phone.slice(5)}</span>
                <span className="text-[10px] font-bold text-gray-500 shrink-0">{c.bills} bill{c.bills === 1 ? '' : 's'} · {formatCurrency(c.totalSpent)}</span>
              </div>
              <p className="text-[12px] font-bold text-[#374151] truncate">{c.name || 'Walk-in Customer'}</p>
              {c.address && <p className="text-[11px] text-gray-500 truncate">{c.address}</p>}
              {c.lastDate && <p className="text-[10px] text-gray-400">Last bill {new Date(c.lastDate).toLocaleDateString('en-IN')}</p>}
            </button>
          ))}
        </div>,
        document.body,
      )}
    </>
  )
}
