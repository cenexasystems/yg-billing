import JsBarcode from 'jsbarcode'
import { getDefaultBarcodeSettings } from './brand'

/** Normalize any scanned or user-entered barcode to a consistent UPPERCASE trimmed string. */
export const normalizeBarcode = (code: string | null | undefined): string => {
  return (code ?? '').trim().toUpperCase()
}

export interface LabelSizeConfig {
  id: string
  name: string
  labelsPerRow: number
  widthMm: number
  heightMm: number
  horizontalGapMm: number
  isCustom?: boolean
}

export const DEFAULT_LABEL_SIZES: LabelSizeConfig[] = [
  { id: '1_35x22', name: '35 × 22 mm (Compact Tag)', labelsPerRow: 1, widthMm: 35, heightMm: 22, horizontalGapMm: 0 },
  { id: '2_38x25', name: '38 × 25 mm (Tag / Jewelry)', labelsPerRow: 1, widthMm: 38, heightMm: 25, horizontalGapMm: 0 },
  { id: '1_50x25', name: '50 × 25 mm (Standard Compact)', labelsPerRow: 1, widthMm: 50, heightMm: 25, horizontalGapMm: 0 },
  { id: '2_50x25', name: '50 × 38 mm (Retail Standard)', labelsPerRow: 1, widthMm: 50, heightMm: 38, horizontalGapMm: 0 },
  { id: '1_60x40', name: '60 × 40 mm (Shipping / Product)', labelsPerRow: 1, widthMm: 60, heightMm: 40, horizontalGapMm: 0 },
  { id: '1_100x50', name: '100 × 50 mm (Large Carton / Box)', labelsPerRow: 1, widthMm: 100, heightMm: 50, horizontalGapMm: 0 },
  { id: '2up_35x22', name: '35 × 22 mm × 2-Up (Roll, side-by-side)', labelsPerRow: 2, widthMm: 35, heightMm: 22, horizontalGapMm: 2 },
  { id: '2up_50x25', name: '50 × 25 mm × 2-Up (Roll, side-by-side)', labelsPerRow: 2, widthMm: 50, heightMm: 25, horizontalGapMm: 2 },
  { id: '3up_35x22', name: '35 × 22 mm × 3-Up (Roll, side-by-side)', labelsPerRow: 3, widthMm: 31.5, heightMm: 20.5, horizontalGapMm: 2 },
  { id: 'a4_4_48x25', name: 'A4 Sheet — 4 columns × 48 × 25 mm', labelsPerRow: 4, widthMm: 48, heightMm: 25, horizontalGapMm: 2 },
  { id: 'a4_4_48x30', name: 'A4 Sheet — 4 columns × 48 × 30 mm', labelsPerRow: 4, widthMm: 48, heightMm: 30, horizontalGapMm: 2 },
  { id: 'a4_3_63x38', name: 'A4 Sheet — 3 columns × 63 × 38 mm', labelsPerRow: 3, widthMm: 63, heightMm: 38, horizontalGapMm: 2 },
  { id: 'a4_2_99x34', name: 'A4 Sheet — 2 columns × 99 × 34 mm (Address label)', labelsPerRow: 2, widthMm: 99, heightMm: 34, horizontalGapMm: 2 },
]

export interface BarcodeSettings {
  printerType: 'label' | 'regular'
  selectedSizeId: string
  showSalePrice: boolean
  showCompanyName: boolean
  showItemName: boolean
  showDiscount: boolean
}

export const DEFAULT_BARCODE_SETTINGS: BarcodeSettings = {
  printerType: 'label',
  selectedSizeId: '2_38x25',
  showSalePrice: true,
  showCompanyName: true,
  showItemName: true,
  showDiscount: false,
}

const SETTINGS_KEY = 'yg_barcode_settings'
const LEGACY_SETTINGS_KEY = 'clad_barcode_settings'
const CUSTOM_SIZES_KEY = 'yg_custom_label_sizes'
const LEGACY_CUSTOM_SIZES_KEY = 'clad_custom_label_sizes'

const branchKey = (key: string, branch?: string) => branch ? `${key}_${branch}` : key

export function getStoredBarcodeSettings(branch?: string): BarcodeSettings {
  try {
    const scopedKey = branchKey(SETTINGS_KEY, branch)
    const raw = localStorage.getItem(scopedKey) || (!branch || branch === 'pos1' ? localStorage.getItem(SETTINGS_KEY) || localStorage.getItem(LEGACY_SETTINGS_KEY) : null)
    if (raw) {
      const stored = JSON.parse(raw)
      return { ...DEFAULT_BARCODE_SETTINGS, ...stored }
    }
  } catch (e) {
    console.error('Failed to parse barcode settings:', e)
  }

  // Nothing saved yet: use this branch's defaults
  return { ...DEFAULT_BARCODE_SETTINGS, ...getDefaultBarcodeSettings(branch) }
}

export function saveStoredBarcodeSettings(settings: BarcodeSettings, branch?: string): void {
  try {
    localStorage.setItem(branchKey(SETTINGS_KEY, branch), JSON.stringify(settings))
  } catch (e) {
    console.error('Failed to save barcode settings:', e)
  }
}

export function getStoredCustomSizes(branch?: string): LabelSizeConfig[] {
  try {
    const scopedKey = branchKey(CUSTOM_SIZES_KEY, branch)
    const raw = localStorage.getItem(scopedKey) || (!branch || branch === 'pos1' ? localStorage.getItem(CUSTOM_SIZES_KEY) || localStorage.getItem(LEGACY_CUSTOM_SIZES_KEY) : null)
    if (raw) return JSON.parse(raw)
  } catch (e) {
    console.error('Failed to parse custom label sizes:', e)
  }
  return []
}

export function saveStoredCustomSize(size: LabelSizeConfig, branch?: string): LabelSizeConfig[] {
  const existing = getStoredCustomSizes(branch).filter((s) => s.id !== size.id)
  const updated = [...existing, { ...size, isCustom: true }]
  try {
    localStorage.setItem(branchKey(CUSTOM_SIZES_KEY, branch), JSON.stringify(updated))
  } catch (e) {
    console.error('Failed to save custom label size:', e)
  }
  return updated
}

export function getAllLabelSizes(branch?: string): LabelSizeConfig[] {
  return [...DEFAULT_LABEL_SIZES, ...getStoredCustomSizes(branch)]
}

export interface BarcodeQueueItem {
  id: string
  productId: number
  productName: string
  variantId?: string | null
  variantName?: string
  barcodeValue: string
  price: number
  costPrice?: number
  noOfLabels: number
  header: string
  line1: string
  line2: string
  line3: string
  line4: string
  selected: boolean
}

export interface BarcodeRenderOptions {
  width?: number
  height?: number
  displayValue?: boolean
  fontSize?: number
  font?: string
  textMargin?: number
  margin?: number
  lineColor?: string
  background?: string
}

/**
 * Render a CODE128 barcode directly into an SVG element.
 */
export function renderBarcodeSvg(
  svgElement: SVGSVGElement,
  value: string,
  options?: BarcodeRenderOptions
) {
  if (!svgElement || !value) return

  try {
    JsBarcode(svgElement, value.trim(), {
      format: 'CODE128',
      width: options?.width ?? 1.5,
      height: options?.height ?? 36,
      displayValue: options?.displayValue ?? true,
      fontSize: options?.fontSize ?? 11,
      font: options?.font ?? 'monospace',
      textMargin: options?.textMargin ?? 1,
      margin: options?.margin ?? 4,
      lineColor: options?.lineColor ?? '#000000',
      background: options?.background ?? '#ffffff',
    })
  } catch (err) {
    console.error('[renderBarcodeSvg] Failed to generate barcode:', err)
  }
}

/**
 * Generate a standalone SVG string for a CODE128 barcode.
 * Executes synchronously in the browser without requiring external CDN scripts.
 */
export function generateBarcodeSvgString(
  value: string,
  options?: BarcodeRenderOptions
): string {
  if (typeof document === 'undefined' || !value) return ''
  try {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    renderBarcodeSvg(svg, value, options)
    return svg.outerHTML || new XMLSerializer().serializeToString(svg)
  } catch (err) {
    console.error('[generateBarcodeSvgString] Failed to generate barcode SVG string:', err)
    return ''
  }
}

export type PrintBarcode = { svg: string; widthMm: number; heightMm: number; moduleMm: number }

/**
 * Barcode SVG for printed stickers, sized so scanners can read it:
 * - every bar is a whole number of printer dots (203 dpi thermal / 600 dpi desktop),
 *   so bars don't come out uneven from fractional scaling;
 * - a white quiet zone is kept on both sides (scanners need it to find the code);
 * - the SVG carries its exact size in mm and must not be stretched by CSS.
 */
export function buildPrintBarcode(
  value: string,
  opts: { labelWidthMm: number; labelHeightMm: number; thermal: boolean },
): PrintBarcode | null {
  if (typeof document === 'undefined' || !value.trim()) return null
  try {
    const probe = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    JsBarcode(probe, value.trim(), { format: 'CODE128', width: 1, height: 10, margin: 0, displayValue: false })
    const modules = parseFloat(probe.getAttribute('width') || '0')
    if (!modules) return null

    const dotMm = 25.4 / (opts.thermal ? 203 : 600)
    const maxModuleMm = 0.38
    const usableMm = opts.labelWidthMm - 0.4
    let quiet = 6
    let moduleMm = dotMm
    // Prefer a wide quiet zone, then the thickest bars that still fit.
    for (const q of [10, 8, 6]) {
      const dots = Math.min(Math.floor(usableMm / ((modules + 2 * q) * dotMm)), Math.floor(maxModuleMm / dotMm))
      if (dots * dotMm >= (opts.thermal ? 2 * dotMm : 0.2)) { quiet = q; moduleMm = dots * dotMm; break }
      if (q === 6) { quiet = 6; moduleMm = Math.max(1, dots) * dotMm }
    }

    const barMm = Math.max(5, opts.labelHeightMm * 0.32)
    const textMm = Math.max(1.8, Math.min(3, opts.labelHeightMm * 0.09))
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    JsBarcode(svg, value.trim(), {
      format: 'CODE128',
      width: 1, // 1 SVG unit = 1 module; scaled to mm below
      height: barMm / moduleMm,
      margin: 0,
      marginLeft: quiet,
      marginRight: quiet,
      displayValue: true,
      fontSize: textMm / moduleMm,
      font: 'Arial, sans-serif',
      fontOptions: 'bold',
      textMargin: 0.3 / moduleMm,
      lineColor: '#000000',
      background: '#ffffff',
    })
    const widthMm = parseFloat(svg.getAttribute('width') || '0') * moduleMm
    const heightMm = parseFloat(svg.getAttribute('height') || '0') * moduleMm
    svg.setAttribute('width', `${widthMm.toFixed(3)}mm`)
    svg.setAttribute('height', `${heightMm.toFixed(3)}mm`)
    svg.setAttribute('shape-rendering', 'crispEdges')
    svg.setAttribute('class', 'print-barcode')
    return { svg: svg.outerHTML || new XMLSerializer().serializeToString(svg), widthMm, heightMm, moduleMm }
  } catch (err) {
    console.error('[buildPrintBarcode] Failed to generate barcode:', err)
    return null
  }
}

/** CSS for `.print-barcode` inside a sticker: exact size, never scaled. */
export const PRINT_BARCODE_CSS = `
  .print-barcode {
    display: block;
    flex-shrink: 0;
    max-width: none !important;
    max-height: none !important;
    shape-rendering: crispEdges;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
`

/**
 * Format barcode for UI display.
 */
export function formatBarcodeDisplay(value?: string | null): string {
  if (!value) return '—'
  return String(value).trim()
}

/**
 * Validate barcode format (alphanumeric, 4 to 32 chars).
 */
export function isValidBarcodeValue(value: string): boolean {
  return /^[A-Z0-9_-]{4,32}$/i.test(value.trim())
}
