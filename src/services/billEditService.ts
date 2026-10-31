import { supabase } from '../lib/supabase'
import { formatInvoiceNo } from '../lib/retail'
import type { PosBranch } from '../store/store'

/** One line of a saved bill, as stored in orders.items */
export type BillLine = Record<string, unknown>

export type BillEditLine = {
  /** Index of the line in the original bill */
  index: number
  name: string
  qty: number
  price: number
  /** Billing-only (typed-in) items have no stock to adjust */
  stocked: boolean
  productId: number | null
  variantId: string | null
}

export type BillTotals = {
  subtotal: number
  couponDiscount: number
  manualDiscount: number
  gst: number
  delivery: number
  total: number
}

const round2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100

export const isStockedLine = (line: BillLine) => {
  const category = String(line.category || '').trim().toLowerCase()
  return !line.is_manual && line.source !== 'manual' && category !== 'unregistered' && line.product_id != null && line.product_id !== ''
}

export const toEditLines = (items: BillLine[]): BillEditLine[] => items.map((line, index) => ({
  index,
  name: String(line.name || line.product_name || 'Item'),
  qty: Number(line.quantity ?? line.qty ?? 1) || 0,
  price: Number(line.base_price ?? line.unit_price ?? line.price ?? 0) || 0,
  stocked: isStockedLine(line),
  productId: line.product_id != null && line.product_id !== '' ? Number(line.product_id) : null,
  variantId: line.variant_id ? String(line.variant_id) : null,
}))

/**
 * GST rate the bill was charged at, worked out from its saved amounts
 * (e.g. ₹90.72 GST on ₹504 taxable = 18%).
 */
export const billGstRate = (order: { total_gst?: number; discount_amount?: number; manual_discount_amount?: number }, originalSubtotal: number) => {
  const taxable = originalSubtotal - (Number(order.discount_amount) || 0) - (Number(order.manual_discount_amount) || 0)
  const gst = Number(order.total_gst) || 0
  if (taxable <= 0 || gst <= 0) return 0
  return Math.round((gst / taxable) * 100 * 100) / 100
}

/** Recalculate a bill the same way the POS does: subtotal → coupon → discount → GST → delivery. */
export const calcBillTotals = (input: {
  lines: Array<{ qty: number; price: number }>
  couponPercentage: number
  /** Used only when the coupon has no percentage (a fixed amount) */
  fixedCoupon: number
  manualDiscount: number
  gstRate: number
  delivery: number
}): BillTotals => {
  const subtotal = round2(input.lines.reduce((s, l) => s + round2(l.qty * l.price), 0))
  const couponDiscount = input.couponPercentage > 0
    ? round2(subtotal * input.couponPercentage / 100)
    : Math.min(round2(input.fixedCoupon), subtotal)
  const manualDiscount = Math.min(Math.max(0, round2(input.manualDiscount)), Math.max(0, subtotal - couponDiscount))
  const taxable = Math.max(0, subtotal - couponDiscount - manualDiscount)
  const gst = round2(taxable * input.gstRate / 100)
  const delivery = round2(input.delivery)
  return { subtotal, couponDiscount, manualDiscount, gst, delivery, total: round2(taxable + gst + delivery) }
}

/**
 * Save an edited bill: the bill itself, its item rows, and stock for any
 * quantity change (logged in stock history as a correction).
 * Returns the problems that happened after the bill was saved, if any.
 */
export async function saveEditedBill(params: {
  orderId: string
  invoiceNo: string
  branch: PosBranch
  originalItems: BillLine[]
  lines: BillEditLine[]
  totals: BillTotals
  customerName: string
  phone: string
  paymentMode: string
  editItems: boolean
}): Promise<{ items: BillLine[]; warnings: string[] }> {
  const { orderId, branch, originalItems, lines, totals } = params
  const invoiceLabel = formatInvoiceNo(params.invoiceNo)

  const kept = new Map(lines.map((l) => [l.index, l]))
  const newItems: BillLine[] = params.editItems
    ? originalItems.flatMap((orig, index) => {
        const l = kept.get(index)
        if (!l) return []
        return [{ ...orig, quantity: l.qty, base_price: l.price, line_total: round2(l.qty * l.price) }]
      })
    : originalItems

  const changes: Record<string, unknown> = {
    customer_name: params.customerName.trim(),
    phone: params.phone.trim(),
    payment_mode: params.paymentMode,
    payment_method: params.paymentMode,
  }
  if (params.editItems) {
    Object.assign(changes, {
      items: newItems,
      subtotal: totals.subtotal,
      discount_amount: totals.couponDiscount,
      manual_discount_amount: totals.manualDiscount,
      manual_discount_type: 'flat',
      manual_discount_value: totals.manualDiscount,
      total_gst: totals.gst,
      gst_amount: totals.gst,
      total: totals.total,
    })
  }

  // 1. The bill itself. A blocked update returns no error and no rows.
  const { data, error } = await supabase.from('orders').update(changes).eq('id', orderId).eq('branch', branch).select('id')
  if (error) throw error
  if (!data || data.length === 0) throw new Error('Changes were not saved. Please log in again as admin and retry.')
  if (!params.editItems) return { items: newItems, warnings: [] }

  const warnings: string[] = []

  // 2. The separate item rows (used by reports)
  try {
    const { data: rows } = await supabase.from('order_items').select('id, product_id, variant_id, name, product_name').eq('order_id', orderId).order('id')
    const used = new Set<number>()
    for (const orig of originalItems.map((o, index) => ({ o, index }))) {
      const row = (rows || []).find((r) => !used.has(Number(r.id))
        && String(r.product_id ?? '') === String(orig.o.product_id ?? '')
        && String(r.variant_id ?? '') === String(orig.o.variant_id ?? '')
        && String(r.name || r.product_name || '') === String(orig.o.name || orig.o.product_name || ''))
        || (rows || []).find((r) => !used.has(Number(r.id))
        && String(r.product_id ?? '') === String(orig.o.product_id ?? '')
        && String(r.variant_id ?? '') === String(orig.o.variant_id ?? ''))
      if (!row) continue
      used.add(Number(row.id))
      const l = kept.get(orig.index)
      if (!l) {
        await supabase.from('order_items').delete().eq('id', row.id)
      } else {
        await supabase.from('order_items').update({
          quantity: l.qty, base_price: l.price, unit_price: l.price, line_total: round2(l.qty * l.price),
        }).eq('id', row.id)
      }
    }
  } catch {
    warnings.push('Item rows for reports could not be fully updated.')
  }

  // 3. Stock: put back what was removed, take what was added
  const deltas = new Map<string, { productId: number; variantId: string | null; name: string; delta: number }>()
  originalItems.forEach((orig, index) => {
    if (!isStockedLine(orig)) return
    const before = Number(orig.quantity ?? orig.qty ?? 0) || 0
    const after = kept.get(index)?.qty ?? 0
    if (after === before) return
    const key = `${orig.product_id}|${orig.variant_id ?? ''}`
    const cur = deltas.get(key) || { productId: Number(orig.product_id), variantId: orig.variant_id ? String(orig.variant_id) : null, name: String(orig.name || 'Item'), delta: 0 }
    cur.delta += after - before
    deltas.set(key, cur)
  })
  for (const d of deltas.values()) {
    if (d.delta === 0) continue
    try {
      const stockRow = d.variantId
        ? await supabase.from('product_variants').select('stock').eq('id', d.variantId).eq('branch', branch).maybeSingle()
        : await supabase.from('products').select('stock_quantity').eq('id', d.productId).eq('branch', branch).maybeSingle()
      if (stockRow.error || !stockRow.data) throw stockRow.error || new Error('not found')
      const current = Number((stockRow.data as Record<string, unknown>).stock ?? (stockRow.data as Record<string, unknown>).stock_quantity ?? 0) || 0
      const { error: adjErr } = await supabase.rpc('adjust_inventory_stock', {
        p_product_id: d.productId,
        p_variant_id: d.variantId,
        p_new_quantity: Math.max(0, current - d.delta),
        p_reason: 'CORRECTION',
        p_note: `Bill ${invoiceLabel} edited (${d.delta > 0 ? `+${d.delta}` : d.delta} sold)`,
        p_created_by_name: 'Admin',
      })
      if (adjErr) throw adjErr
    } catch {
      warnings.push(`Stock for "${d.name}" could not be adjusted by ${-d.delta}. Please correct it in Stock & Inventory.`)
    }
  }

  return { items: newItems, warnings }
}
