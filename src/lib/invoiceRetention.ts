import { supabase } from './supabase'

/**
 * Invoice PDFs live in Supabase Storage, which has a small free quota.
 * Only the Fireworks (POS 2) PDFs are limited: the newest KEEP_INVOICE_PDFS are kept and older ones are removed.
 * POS 1 and Christmas (POS 3) PDFs are never touched.
 * A removed PDF is not lost: opening, downloading or printing that invoice rebuilds it from the order.
 *
 * The counter is read from the invoice number in the file name.
 * Fireworks = below 10000001, or 50000001-59999999 (older bills).
 */
export const KEEP_INVOICE_PDFS = 200

const BUCKET = 'invoices'
const FOLDER = 'invoices'
const LAST_RUN_KEY = 'yg_invoice_pdf_prune_at'
const MIN_INTERVAL_MS = 30 * 60 * 1000

type StoredFile = { name: string; created_at: string }

const isFireworksFile = (name: string) => {
  const m = /^(.*)-\d{10,}\.pdf$/i.exec(name)
  if (!m || !/^\d{8}$/.test(m[1])) return false // unknown / legacy names are never touched
  const n = Number(m[1])
  return n < 10000001 || (n >= 50000001 && n < 60000000)
}

async function listAllFiles(): Promise<StoredFile[]> {
  const all: StoredFile[] = []
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.storage.from(BUCKET).list(FOLDER, {
      limit: 1000, offset, sortBy: { column: 'created_at', order: 'desc' },
    })
    if (error) throw error
    const rows = (data || []).filter((f) => f.name && f.name.toLowerCase().endsWith('.pdf')) as unknown as StoredFile[]
    all.push(...rows)
    if (!data || data.length < 1000) break
  }
  return all
}

/** Remove surplus invoice PDFs. Safe to call often: it runs at most every 30 minutes unless forced. */
export async function pruneInvoicePdfs(opts: { force?: boolean } = {}): Promise<{ removed: number }> {
  try {
    if (!opts.force) {
      const last = Number(localStorage.getItem(LAST_RUN_KEY) || 0)
      if (Date.now() - last < MIN_INTERVAL_MS) return { removed: 0 }
    }
    localStorage.setItem(LAST_RUN_KEY, String(Date.now()))
  } catch { /* storage unavailable: just run */ }

  try {
    const files = await listAllFiles() // newest first
    const doomed = files.filter((f) => isFireworksFile(f.name)).slice(KEEP_INVOICE_PDFS) // newest first
    if (doomed.length === 0) return { removed: 0 }

    let removed = 0
    for (let i = 0; i < doomed.length; i += 100) {
      const chunk = doomed.slice(i, i + 100)
      const paths = chunk.map((f) => `${FOLDER}/${f.name}`)
      const { error } = await supabase.storage.from(BUCKET).remove(paths)
      if (error) throw error
      removed += paths.length
      // Orders that pointed at a removed file fall back to a PDF rebuilt on demand
      const urls = paths.map((p) => supabase.storage.from(BUCKET).getPublicUrl(p).data.publicUrl)
      await supabase.from('orders').update({ invoice_pdf_url: null }).in('invoice_pdf_url', urls)
    }
    return { removed }
  } catch (err) {
    console.warn('Invoice PDF cleanup skipped:', err)
    return { removed: 0 }
  }
}
