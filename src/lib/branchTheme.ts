import { useSettingsStore, POS_BRANCHES, type PosBranch, type ActiveBranch, type AdminRole, type StoreSettings } from '../store/store'
import { normalizeHex, shadeHex, tintHex, mixHex } from './color'
import { BRAND_LOGO_POS1, BRAND_LOGO_POS2, BRAND_LOGO_POS3 } from './brand'

/** User-facing branch name, themed to what that branch actually sells
 * (not a generic "POS 1"/"POS 2") — keep this the single source of truth
 * for the branch name shown anywhere in the UI. */
export const branchLabel = (branch: PosBranch) =>
  branch === 'pos3' ? 'Christmas POS' : branch === 'pos2' ? 'Fireworks & Crackers POS' : 'Jute & Wedding POS'

/** Short chip/badge form of branchLabel for tight spaces (nav pills, badges). */
export const branchShortLabel = (branch: PosBranch) =>
  branch === 'pos3' ? 'Christmas POS' : branch === 'pos2' ? 'Fireworks POS' : 'Jute & Wedding POS'

/** What this branch actually sells, for taglines/subtitles (matches the
 * wording baked into each branch's own logo art and Store Settings
 * business_type). */
export const branchSubtitle = (branch: PosBranch) =>
  branch === 'pos3' ? 'Christmas Stock' : branch === 'pos2' ? 'Fireworks & Crackers' : 'Wedding Card, Wedding Bag and Jute Bag Manufacturing'

/** Combined tagline for admin/global contexts that span both branches
 * (e.g. the Admin Orchestrator login tab) — showing only one branch's
 * business line there would be misleading since admin manages both. */
export const combinedBranchSubtitle = () => POS_BRANCHES.map((b) => branchSubtitle(b)).join(' + ')

export const branchLogo = (branch: PosBranch) =>
  useSettingsStore.getState().settingsByBranch[branch]?.logoUrl || (branch === 'pos3' ? BRAND_LOGO_POS3 : branch === 'pos2' ? BRAND_LOGO_POS2 : BRAND_LOGO_POS1)

export const posAccent = (branch: PosBranch) => branch === 'pos3'
  ? { bg: 'bg-posThree', bgLight: 'bg-posThree-light', text: 'text-posThree-dark', border: 'border-posThree', hex: '#1E7B43' }
  : branch === 'pos2'
  ? { bg: 'bg-posTwo', bgLight: 'bg-posTwo-light', text: 'text-posTwo-dark', border: 'border-posTwo', hex: '#B8860B' }
  : { bg: 'bg-posOne', bgLight: 'bg-posOne-light', text: 'text-posOne-dark', border: 'border-posOne', hex: '#8B1A1A' }

export const DEFAULT_BRANCH_COLOR: Record<PosBranch, string> = { pos1: '#8B1A1A', pos2: '#B8860B', pos3: '#1E7B43' }
export const DEFAULT_ADMIN_COLOR = '#7A1220'

const ADMIN_THEME_STORAGE_KEY = 'yg_admin_theme_color'

export function getAdminThemeColor(): string {
  try {
    const saved = localStorage.getItem(ADMIN_THEME_STORAGE_KEY)
    if (saved) return normalizeHex(saved)
  } catch { /* ignore */ }
  return DEFAULT_ADMIN_COLOR
}

export function setAdminThemeColor(hex: string): void {
  try {
    const normalized = normalizeHex(hex)
    localStorage.setItem(ADMIN_THEME_STORAGE_KEY, normalized)
  } catch { /* ignore */ }
}

/** Pushes each branch's saved Appearance color (Store Settings) onto the
 * `--pos-one*` / `--pos-two*` CSS custom properties that `bg-posOne`,
 * `text-posTwo-dark`, etc. resolve to (see tailwind.config.js), so the
 * picked color actually retheme's that branch's admin UI. */
export function applyBranchThemeVars(settingsByBranch: Partial<Record<PosBranch, StoreSettings>>) {
  const root = document.documentElement
  POS_BRANCHES.forEach((branch) => {
    const varPrefix = branch === 'pos3' ? '--pos-three' : branch === 'pos2' ? '--pos-two' : '--pos-one'
    const color = normalizeHex(settingsByBranch[branch]?.themeColor || DEFAULT_BRANCH_COLOR[branch])
    root.style.setProperty(varPrefix, color)
    root.style.setProperty(`${varPrefix}-dark`, shadeHex(color))
    root.style.setProperty(`${varPrefix}-light`, tintHex(color))
  })
}

/** Determines active theme color based on current role, activeBranch, and saved preferences,
 * and sets root CSS variables so the ENTIRE theme changes dynamically. */
export function applyActiveTheme(
  activeBranch: ActiveBranch,
  role: AdminRole,
  settingsByBranch: Partial<Record<PosBranch, StoreSettings>>,
  staffBranch?: PosBranch | null
) {
  const root = document.documentElement

  // Update branch vars first
  applyBranchThemeVars(settingsByBranch)

  let activeColor = DEFAULT_ADMIN_COLOR

  if (role === 'staff' && staffBranch) {
    activeColor = normalizeHex(settingsByBranch[staffBranch]?.themeColor || DEFAULT_BRANCH_COLOR[staffBranch])
  } else if (activeBranch === 'pos1') {
    activeColor = normalizeHex(settingsByBranch['pos1']?.themeColor || DEFAULT_BRANCH_COLOR['pos1'])
  } else if (activeBranch === 'pos2') {
    activeColor = normalizeHex(settingsByBranch['pos2']?.themeColor || DEFAULT_BRANCH_COLOR['pos2'])
  } else if (activeBranch === 'pos3') {
    activeColor = normalizeHex(settingsByBranch['pos3']?.themeColor || DEFAULT_BRANCH_COLOR['pos3'])
  } else {
    // Admin global / all branches view
    activeColor = getAdminThemeColor()
  }

  const primaryDark = shadeHex(activeColor, 0.28)
  const primaryLight = tintHex(activeColor, 0.90)
  const primaryBorder = mixHex(activeColor, '#D4AF37', 0.35)

  root.style.setProperty('--theme-primary', activeColor)
  root.style.setProperty('--theme-primary-dark', primaryDark)
  root.style.setProperty('--theme-primary-light', primaryLight)
  root.style.setProperty('--theme-primary-border', primaryBorder)

  // Map brand-black variables to the active theme color
  root.style.setProperty('--brand-black', activeColor)
  root.style.setProperty('--brand-black-surface', primaryDark)
}
