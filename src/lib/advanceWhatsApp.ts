import { getAdvanceOrderHistory, type AdvanceOrder } from '../services/advanceOrderService'
import { buildAdvanceCalculationWhatsAppMessage } from './whatsappMessage'

/**
 * Fireworks (POS 2) advance-order WhatsApp text: the full calculation with
 * payment splits, and no invoice or website links. Amounts come from the
 * saved payment records, so any screen produces the same message.
 */
export async function buildFireworksAdvanceMessage(
  order: AdvanceOrder,
  known: { depositMethod?: string | null; balancePaid?: number; balanceMethod?: string | null; adjustment?: number } = {},
): Promise<string> {
  let payments: Array<{ payment_type: string; amount: number; payment_method: string }> = []
  try {
    payments = (await getAdvanceOrderHistory(order.id)).payments
  } catch { /* fall back to the order's own amounts */ }

  const deposit = payments.find((p) => p.payment_type === 'deposit')
  const remaining = payments.filter((p) => p.payment_type === 'remaining')
  const depositAmount = deposit ? Number(deposit.amount) || 0 : Number(order.deposit_amount) || 0
  const completed = order.status === 'completed' || !!order.invoice_number
  const remainingPaid = remaining.length ? remaining.reduce((s, p) => s + (Number(p.amount) || 0), 0) : undefined
  const balanceDue = Math.max(0, (Number(order.total_amount) || 0) - depositAmount)
  const balancePaid = known.balancePaid ?? remainingPaid ?? balanceDue

  const items = (order.products?.length ? order.products : [{ name: order.product_name, quantity: 1, line_total: order.total_amount }])
    .map((p) => ({
      name: String(p.name || p.product_name || 'Product'),
      qty: Number(p.quantity ?? p.qty ?? 1) || 1,
      lineTotal: Number(p.line_total ?? 0) || 0,
    }))

  return buildAdvanceCalculationWhatsAppMessage({
    customerName: order.customer_name,
    depositId: order.deposit_id,
    invoiceNumber: order.invoice_number,
    items,
    totalAmount: Number(order.total_amount) || 0,
    depositAmount,
    depositMethod: known.depositMethod ?? deposit?.payment_method,
    completed,
    balancePaid,
    balanceMethod: known.balanceMethod ?? order.final_payment_method ?? remaining[0]?.payment_method,
    adjustment: known.adjustment ?? Math.max(0, balanceDue - balancePaid),
    expectedDeliveryDate: order.expected_delivery_date,
    branch: order.branch,
  })
}
