import { roundTo } from './retail'

export type GstSplit = {
  cgst: number
  sgst: number
  /** CGST / SGST rate as display text (e.g. "9%"), or '' when it can't be known. */
  halfRateLabel: string
}

const rateText = (rate: number) => `${Number(rate.toFixed(2))}%`

/**
 * Splits a bill's GST equally into CGST and SGST (intra-state supply).
 *
 * Bills store only the GST amount, so when the rate isn't supplied it is
 * worked out from the taxable value (subtotal after discounts). A rate is
 * only shown if it reproduces the stored amount exactly; a flat GST amount
 * that doesn't correspond to a clean rate is shown without a percentage.
 */
export function splitGst(gstAmount: number, taxableValue: number, gstRatePercent?: number | null): GstSplit {
  const total = roundTo(Math.max(0, Number(gstAmount) || 0), 2)
  const cgst = roundTo(total / 2, 2)
  const sgst = roundTo(total - cgst, 2)

  let rate = gstRatePercent != null && gstRatePercent > 0 ? gstRatePercent : null
  const taxable = Number(taxableValue) || 0
  if (rate == null && total > 0 && taxable > 0) {
    const derived = roundTo((total / taxable) * 100, 2)
    if (Math.abs(roundTo((taxable * derived) / 100, 2) - total) < 0.005) rate = derived
  }

  return { cgst, sgst, halfRateLabel: rate ? rateText(rate / 2) : '' }
}
