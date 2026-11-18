import { useState } from 'react'
import { ShieldCheck, User, KeyRound, Eye, EyeOff, Save, Loader2 } from 'lucide-react'
import { posAccent, branchLabel } from '../../lib/branchTheme'
import { updateCredentialPassword, type CredentialRoleKey } from '../../services/credentialService'
import type { PosBranch } from '../../store/store'

type RosterEntry = {
  id: string
  label: string
  role: 'ADMIN' | 'STAFF'
  branch: PosBranch | 'all'
  roleKey: CredentialRoleKey
}

function buildRoster(): RosterEntry[] {
  const adminId = String(import.meta.env.VITE_ADMIN_ID || import.meta.env.VITE_PORTAL_ID || 'admin').trim()
  const pos1Id = String(import.meta.env.VITE_POS1_STAFF_ID || import.meta.env.VITE_STAFF_ID || 'staff').trim()
  const pos2Id = String(import.meta.env.VITE_POS2_STAFF_ID || '').trim()
  const pos3Id = String(import.meta.env.VITE_POS3_STAFF_ID || 'staff3').trim()

  const roster: RosterEntry[] = [
    { id: adminId, label: adminId, role: 'ADMIN', branch: 'all', roleKey: 'admin' },
    { id: pos1Id, label: pos1Id, role: 'STAFF', branch: 'pos1', roleKey: 'pos1_staff' },
  ]
  if (pos2Id) {
    roster.push({ id: pos2Id, label: pos2Id, role: 'STAFF', branch: 'pos2', roleKey: 'pos2_staff' })
  }
  if (pos3Id) {
    roster.push({ id: pos3Id, label: pos3Id, role: 'STAFF', branch: 'pos3', roleKey: 'pos3_staff' })
  }
  return roster
}

function PasswordRow({ entry }: { entry: RosterEntry }) {
  const accent = entry.branch === 'all' ? null : posAccent(entry.branch)
  const [value, setValue] = useState('')
  const [show, setShow] = useState(false)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  const handleSave = async () => {
    setSaving(true)
    setMessage(null)
    try {
      await updateCredentialPassword(entry.roleKey, value)
      setMessage({ type: 'success', text: 'Password updated.' })
      setValue('')
    } catch (err) {
      setMessage({ type: 'error', text: err instanceof Error ? err.message : 'Failed to update password' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <li className="p-4 flex flex-wrap items-center justify-between gap-3">
      <div className="flex items-center gap-2.5 min-w-[160px]">
        <div className={`w-8 h-8 rounded-full flex items-center justify-center font-black text-[11px] shrink-0 ${accent ? `${accent.bgLight} ${accent.text}` : 'bg-[#FBF6E9] text-[#B48811]'}`}>
          {entry.label.slice(0, 1).toUpperCase()}
        </div>
        <div>
          <p className="text-xs font-black text-[#1A0E0E]">{entry.label}</p>
          <p className="text-[10px] text-gray-400 font-semibold">{entry.branch === 'all' ? 'Admin Orchestrator' : branchLabel(entry.branch)}</p>
        </div>
      </div>
      <div className="flex items-center gap-2 flex-1 min-w-[220px]">
        <div className="relative flex-1">
          <input
            type={show ? 'text' : 'password'}
            value={value}
            onChange={(e) => { setValue(e.target.value); setMessage(null) }}
            placeholder="New password"
            className="w-full h-9 pl-3 pr-9 rounded-xl border border-gray-200 bg-[#FBFAF6] text-xs font-bold outline-none focus:border-gray-400"
          />
          <button
            type="button"
            onClick={() => setShow((s) => !s)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 cursor-pointer"
            aria-label={show ? 'Hide password' : 'Show password'}
          >
            {show ? <EyeOff size={14} /> : <Eye size={14} />}
          </button>
        </div>
        <button
          onClick={() => void handleSave()}
          disabled={saving || value.trim().length < 4}
          className={`flex items-center gap-1.5 px-3 h-9 rounded-xl text-[11px] font-black text-white shrink-0 disabled:opacity-40 cursor-pointer ${accent ? accent.bg : 'bg-[#7A1220]'}`}
        >
          {saving ? <Loader2 size={13} className="animate-spin" /> : <Save size={13} />} Save
        </button>
      </div>
      {message && (
        <p className={`w-full text-[10px] font-bold ${message.type === 'success' ? 'text-emerald-600' : 'text-red-600'}`}>{message.text}</p>
      )}
    </li>
  )
}

export default function StaffMemberships() {
  const roster = buildRoster()

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-xl font-black text-[#1A0E0E]">Staff &amp; Memberships</h2>
          <p className="text-xs text-gray-500 font-semibold mt-1">Configured login accounts and the branch each one is restricted to.</p>
        </div>
        <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 text-[10px] font-black uppercase">
          <ShieldCheck size={13} /> {roster.length} Accounts Configured
        </span>
      </div>

      <div className="bg-white border border-gray-200 rounded-2xl overflow-hidden shadow-sm">
        <div className="p-4 border-b border-gray-200 bg-[#FAFAFA]">
          <p className="text-xs font-black uppercase tracking-wider text-gray-800">Active Staff Roster ({roster.length})</p>
        </div>
        <ul className="divide-y divide-gray-100">
          {roster.map((entry) => {
            const accent = entry.branch === 'all' ? null : posAccent(entry.branch)
            return (
              <li key={`${entry.branch}-${entry.id}`} className="p-4 flex items-center justify-between gap-3 flex-wrap">
                <div className="flex items-center gap-3">
                  <div className={`w-9 h-9 rounded-full flex items-center justify-center font-black text-xs ${accent ? `${accent.bgLight} ${accent.text}` : 'bg-[#FBF6E9] text-[#B48811]'}`}>
                    {entry.label.slice(0, 1).toUpperCase()}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-black text-[#1A0E0E]">{entry.label}</p>
                      <span className={`px-1.5 py-0.5 rounded text-[9px] font-black uppercase tracking-wide ${entry.role === 'ADMIN' ? 'bg-[#FBF6E9] text-[#B48811] border border-[#E8D399]' : 'bg-gray-100 text-gray-600 border border-gray-200'}`}>
                        {entry.role}
                      </span>
                    </div>
                    <p className="text-xs text-gray-400 font-semibold flex items-center gap-1 mt-0.5">
                      <User size={11} /> Portal ID login
                    </p>
                  </div>
                </div>
                <div className="text-right">
                  <p className={`text-xs font-black ${accent ? accent.text : 'text-[#B48811]'}`}>
                    {entry.branch === 'all' ? 'All Branches' : branchLabel(entry.branch)}
                  </p>
                  <p className="text-[10px] text-gray-400 font-semibold flex items-center gap-1 justify-end mt-0.5">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" /> Branch-Restricted Login
                  </p>
                </div>
              </li>
            )
          })}
        </ul>
      </div>

      <div className="bg-white border border-gray-200 rounded-2xl overflow-hidden shadow-sm">
        <div className="p-4 border-b border-gray-200 bg-[#FAFAFA] flex items-center gap-2">
          <KeyRound size={15} className="text-[#7A1220]" />
          <div>
            <p className="text-xs font-black uppercase tracking-wider text-gray-800">Change Portal Passwords</p>
            <p className="text-[10px] text-gray-400 font-semibold">Set a new password for any account — takes effect on that account's next login.</p>
          </div>
        </div>
        <ul className="divide-y divide-gray-100">
          {roster.map((entry) => (
            <PasswordRow key={`pw-${entry.branch}-${entry.id}`} entry={entry} />
          ))}
        </ul>
      </div>

      <p className="text-[10px] text-gray-400 font-semibold">
        Portal IDs come from environment variables; passwords can be overridden above and are stored in the database. Branch restriction is enforced client-side at login, the same trust model as the rest of this portal.
      </p>
    </div>
  )
}
