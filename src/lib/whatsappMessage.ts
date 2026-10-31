import { couponLabel, formatInvoiceNo } from './retail'
import { BRAND_EN, BRAND_PRODUCTION_DOMAIN, BRAND_WEBSITE } from './brand'
import { getBranchProfile } from './branchProfile'

export type WhatsAppLineItem = {
  name: string
  qty: number
  unit: string
  unitType: 'unit' | 'weight' | 'volume' | 'bundle'
  rate: number
  lineTotal: number
}

export type BuildWhatsAppMessageInput = {
  customerName?: string
  phone?: string
  invoiceNumber: string
  invoiceDate?: string
  invoiceUrl?: string
  paymentMode?: string
  items?: WhatsAppLineItem[]
  subtotal?: number
  couponDiscount?: number
  couponCode?: string | null
  couponPercentage?: number | null
  manualDiscountAmount?: number
  shipping?: number
  gstAmount?: number
  total?: number
  branch?: string // POS1 or POS2
}

export type AdvanceDepositWhatsAppInput = {
  customerName?: string
  depositId: string
  productName: string
  totalAmount: number
  depositAmount: number
  remainingBalance: number
  expectedDeliveryDate: string
  paymentMethod?: string
  branch?: string // POS1 or POS2
}

export const publicInvoiceUrl = (invoiceNumber: string) => {
  const formatted = formatInvoiceNo(invoiceNumber)
  const envUrl = (import.meta.env.VITE_SITE_URL as string | undefined)?.replace(/\/$/, '')
  const origin =
    envUrl ||
    (typeof window !== 'undefined' && window.location?.origin && !window.location.origin.includes('localhost')
      ? window.location.origin
      : BRAND_PRODUCTION_DOMAIN)
  return `${origin}/invoice/${encodeURIComponent(formatted)}`
}

export const buildProfessionalWhatsAppMessage = (input: BuildWhatsAppMessageInput) => {
  // Fireworks bills go out as the calculation only, with no invoice or website links
  if (String(input.branch || '').toLowerCase() === 'pos2') return buildFireworksBillWhatsAppMessage(input)
  const customerName = input.customerName?.trim() || 'Valued Customer'
  const invoiceUrl = input.invoiceUrl || publicInvoiceUrl(input.invoiceNumber)
  const formattedNo = formatInvoiceNo(input.invoiceNumber)
  const itemsText = input.items && input.items.length > 0
    ? input.items.map(item => `• ${item.name} (x${item.qty}) - ₹ ${Number(item.lineTotal || 0).toFixed(2)}`).join('\n')
    : ''

  // Instagram URLs (same handles for both branches)
  const profile = getBranchProfile(input.branch)
  const instagramSection = profile.instagramUrls
  const instagramText = instagramSection ? `\n📷 *Follow us on Instagram:*\n${instagramSection}` : ''

  return `✨ *${BRAND_EN}* ✨
🛍️ *Official Purchase Invoice & Receipt* 🛍️

Dear ${customerName},

Thank you for shopping at ${BRAND_EN}! We truly appreciate your patronage.

🧾 *INVOICE DETAILS*
📌 *Invoice No:* #${formattedNo}
${input.invoiceDate ? `📅 *Date:* ${new Date(input.invoiceDate).toLocaleDateString('en-IN')}\n` : ''}${input.paymentMode ? `💳 *Payment Mode:* ${input.paymentMode}\n` : ''}${(input.couponDiscount || 0) > 0 ? `🎟️ *${couponLabel(input.couponCode, input.couponPercentage)}:* -₹ ${Number(input.couponDiscount || 0).toFixed(2)}
` : ''}${input.total !== undefined ? `💰 *Total Amount:* ₹ ${Number(input.total || 0).toFixed(2)}\n` : ''}
${itemsText ? `📦 *ITEMS ORDERED:*\n${itemsText}\n\n` : ''}📄 *View & Download Digital Invoice / PDF:*
👉 ${invoiceUrl}

🌐 *Visit Our Official Website:*
👉 ${BRAND_WEBSITE}

📞 *Shop Contact:* ${profile.phone}${instagramText}

Thank you, and visit us again! ✨`
}

export const buildAdvanceDepositWhatsAppMessage = (input: AdvanceDepositWhatsAppInput) => {
  const customerName = input.customerName?.trim() || 'Valued Customer'
  const deliveryDateFormatted = input.expectedDeliveryDate
    ? (() => {
        try {
          return new Date(`${input.expectedDeliveryDate}T00:00:00`).toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric',
          })
        } catch {
          return input.expectedDeliveryDate
        }
      })()
    : '-'

  // Instagram URLs (same handles for both branches)
  const profile = getBranchProfile(input.branch)
  const instagramUrls = profile.instagramUrls
  const instagramSection = instagramUrls ? `\n📷 *Follow us on Instagram:*\n${instagramUrls}` : ''

  return `✨ *Thank You for Your Advance Order with ${BRAND_EN}!* ✨

Dear ${customerName},

We have successfully received your initial advance payment!

🧾 *Advance Order Details* 👇
📦 Deposit ID: #${input.depositId}
👔 Product: ${input.productName}
💵 Total Order Amount: ₹${input.totalAmount}
💰 Advance Paid: ₹${input.depositAmount}${input.paymentMethod ? ` (${input.paymentMethod.toLowerCase() === 'upi' ? 'QR' : input.paymentMethod.toUpperCase()})` : ''}
🔴 Balance to Pay on Delivery: ₹${input.remainingBalance}
📅 Expected Delivery Date: ${deliveryDateFormatted}

Your order is being prepared with utmost care. We will have everything ready on or before ${deliveryDateFormatted}!

🌐 *Visit Our Official Website:*
👉 ${BRAND_WEBSITE}

📞 *Shop Contact:* ${profile.phone}${instagramSection}`
}

// ── Fireworks (POS 2) advance orders: calculation only, no links ──────────

export type AdvanceCalculationInput = {
  customerName?: string
  depositId: string
  invoiceNumber?: string | null
  items: Array<{ name: string; qty: number; lineTotal: number }>
  totalAmount: number
  depositAmount: number
  depositMethod?: string | null
  /** Set once the balance has been paid */
  completed: boolean
  balancePaid?: number
  balanceMethod?: string | null
  adjustment?: number
  expectedDeliveryDate?: string
  branch?: string
}

const rupees = (n: number) => `₹${(Math.round((Number(n) || 0) * 100) / 100).toFixed(2)}`

/** "upi" → "QR", "cash" → "Cash", ... */
export const paymentMethodLabel = (method?: string | null) => {
  const m = String(method || '').trim()
  const key = m.toLowerCase()
  if (key === 'upi' || key === 'qr') return 'QR'
  if (key === 'cash') return 'Cash'
  if (key === 'card') return 'Card'
  return m ? m.charAt(0).toUpperCase() + m.slice(1) : ''
}

/** "Split (Cash ₹400 + QR ₹250)" → [{ label: 'Cash', amount: 400 }, { label: 'QR', amount: 250 }] */
export const parseSplitPayment = (method?: string | null) => {
  const inner = /split\s*\((.*)\)/i.exec(String(method || ''))?.[1]
  if (!inner) return []
  return inner.split('+').map((part) => {
    const m = /^\s*(.*?)\s*₹\s*([\d.,]+)\s*$/.exec(part)
    return m ? { label: paymentMethodLabel(m[1]), amount: Number(m[2].replace(/,/g, '')) || 0 } : null
  }).filter((p): p is { label: string; amount: number } => !!p)
}

const paymentLines = (title: string, amount: number, method?: string | null) => {
  const splits = parseSplitPayment(method)
  if (splits.length) {
    return [`${title}: ${rupees(amount)} (Split)`, ...splits.map((s) => `    • ${s.label}: ${rupees(s.amount)}`)]
  }
  const label = paymentMethodLabel(method)
  return [`${title}: ${rupees(amount)}${label ? ` (${label})` : ''}`]
}

export const buildAdvanceCalculationWhatsAppMessage = (input: AdvanceCalculationInput) => {
  const profile = getBranchProfile(input.branch)
  const customerName = input.customerName?.trim() || 'Valued Customer'
  const balanceDue = Math.max(0, input.totalAmount - input.depositAmount)
  const adjustment = Math.max(0, Number(input.adjustment) || 0)
  const balancePaid = input.completed ? Math.max(0, input.balancePaid ?? balanceDue - adjustment) : 0
  const totalPaid = input.depositAmount + balancePaid
  const line = '━━━━━━━━━━━━━━'

  const lines: string[] = [
    `✨ *${BRAND_EN}* ✨`,
    input.completed ? '✅ *Advance Order — Fully Paid*' : '🧾 *Advance Order Receipt*',
    '',
    `Dear ${customerName},`,
    '',
    `📦 *Order ID:* #${input.depositId}`,
  ]
  if (input.completed && input.invoiceNumber) lines.push(`🧾 *Invoice No:* #${formatInvoiceNo(input.invoiceNumber)}`)
  if (input.items.length) {
    lines.push('', '*ITEMS:*', ...input.items.map((i) => `• ${i.name} (x${i.qty}) - ${rupees(i.lineTotal)}`))
  }
  lines.push('', line, `Order Total: ${rupees(input.totalAmount)}`, ...paymentLines('Advance Paid', input.depositAmount, input.depositMethod))

  if (input.completed) {
    if (adjustment > 0) lines.push(`Balance: ${rupees(balanceDue)}`, `Adjustment: -${rupees(adjustment)}`)
    lines.push(...paymentLines('Balance Paid', balancePaid, input.balanceMethod), line,
      `*Total Paid: ${rupees(totalPaid)}*`, `*Balance Due: ${rupees(0)}*`)
  } else {
    lines.push(line, `*Balance to Pay on Delivery: ${rupees(balanceDue)}*`)
    if (input.expectedDeliveryDate) {
      let when = input.expectedDeliveryDate
      try {
        when = new Date(`${input.expectedDeliveryDate}T00:00:00`).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
      } catch { /* keep raw date */ }
      lines.push(`📅 Expected Delivery: ${when}`)
    }
  }

  lines.push('', `📞 Shop Contact: ${profile.phone}`, '', input.completed ? 'Thank you for your purchase! ✨' : 'Thank you for your order! ✨')
  return lines.join('\n')
}

/** Fireworks (POS 2) bill: items, every charge/discount and the payment (with splits). No links. */
export const buildFireworksBillWhatsAppMessage = (input: BuildWhatsAppMessageInput) => {
  const profile = getBranchProfile(input.branch)
  const customerName = input.customerName?.trim() || 'Valued Customer'
  const line = '━━━━━━━━━━━━━━'
  const items = input.items || []
  const subtotal = input.subtotal ?? items.reduce((sum, i) => sum + (Number(i.lineTotal) || 0), 0)
  const coupon = Number(input.couponDiscount) || 0
  const manual = Number(input.manualDiscountAmount) || 0
  const gst = Number(input.gstAmount) || 0
  const shipping = Number(input.shipping) || 0

  const lines: string[] = [
    `✨ *${BRAND_EN}* ✨`,
    '🧾 *Bill Details*',
    '',
    `Dear ${customerName},`,
    '',
    `📌 *Invoice No:* #${formatInvoiceNo(input.invoiceNumber)}`,
  ]
  if (items.length) {
    lines.push('', '*ITEMS:*', ...items.map((i) => `• ${i.name} (x${i.qty}) - ${rupees(Number(i.lineTotal) || 0)}`))
  }
  lines.push('', line, `Subtotal: ${rupees(subtotal)}`)
  if (coupon > 0) lines.push(`${couponLabel(input.couponCode, input.couponPercentage)}: -${rupees(coupon)}`)
  if (manual > 0) lines.push(`Discount: -${rupees(manual)}`)
  if (gst > 0) lines.push(`GST: ${rupees(gst)}`)
  if (shipping > 0) lines.push(`Delivery: ${rupees(shipping)}`)
  if (input.total !== undefined) lines.push(`*Total: ${rupees(Number(input.total) || 0)}*`)
  if (input.paymentMode) {
    lines.push(line, ...paymentLines('Paid', Number(input.total) || 0, input.paymentMode))
  } else {
    lines.push(line)
  }
  lines.push('', `📞 Shop Contact: ${profile.phone}`, '', 'Thank you, and visit us again! ✨')
  return lines.join('\n')
}
