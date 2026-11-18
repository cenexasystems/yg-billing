import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { Lock, Eye, EyeOff, AlertCircle, ShieldCheck, Store, ShieldAlert } from 'lucide-react'
import { useAdminAuthStore, POS_BRANCHES, type PosBranch } from '../store/store'
import { BRAND_EN, BRAND_TA, BRAND_LOGO } from '../lib/brand'
import { branchLogo, branchShortLabel, branchSubtitle, combinedBranchSubtitle } from '../lib/branchTheme'
import { useLangStore } from '../store/langStore'
import { alarmSound } from '../lib/alarmAudio'
import CenexaFooter from '../components/common/CenexaFooter'

const BRANCHES: { key: PosBranch; label: string }[] = POS_BRANCHES.map((key) => ({ key, label: branchShortLabel(key) }))

export default function AdminLogin() {
  const navigate = useNavigate()
  const location = useLocation()
  const { lang } = useLangStore()
  const l = (en: string, ta: string) => lang === 'ta' ? ta : en
  const login = useAdminAuthStore((state) => state.login)

  const [loginTab, setLoginTab] = useState<'staff' | 'admin'>('staff')
  const [branch, setBranch] = useState<PosBranch>('pos1')

  const [staffId, setStaffId] = useState('')
  const [staffPassword, setStaffPassword] = useState('')
  const [showStaffPassword, setShowStaffPassword] = useState(false)

  const [adminId, setAdminId] = useState('')
  const [adminPassword, setAdminPassword] = useState('')
  const [showAdminPassword, setShowAdminPassword] = useState(false)

  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const from = (location.state as { from?: Location })?.from?.pathname || '/dashboard'

  const handleStaffSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    void alarmSound.unlock()
    setError('')
    setLoading(true)
    const role = await login(staffId.trim(), staffPassword, branch)
    setLoading(false)
    if (role === 'staff') {
      navigate('/dashboard', { replace: true })
    } else {
      setError(l(`Invalid staff ID or password for ${branchShortLabel(branch)}`, 'தவறான பணியாளர் விவரங்கள்'))
    }
  }

  const handleAdminSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    void alarmSound.unlock()
    setError('')
    setLoading(true)
    const role = await login(adminId.trim(), adminPassword)
    setLoading(false)
    if (role === 'admin') {
      const destination = from === '/pos' ? '/dashboard' : from
      navigate(destination, { replace: true })
    } else {
      setError(l('Invalid admin credentials', 'தவறான நிர்வாகி விவரங்கள்'))
    }
  }

  const switchTab = (tab: 'staff' | 'admin') => {
    setLoginTab(tab)
    setError('')
  }

  return (
    <div className="relative h-[100dvh] max-h-[100dvh] min-h-[100dvh] bg-white font-sans flex flex-col justify-between overflow-hidden">
      <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain p-3 sm:p-5 lg:p-6 flex flex-col items-center">
        <div className="my-auto relative grid w-full max-w-4xl max-h-[92vh] overflow-hidden rounded-3xl border border-gray-200/90 bg-[#5C0D18] shadow-[0_25px_60px_-12px_rgba(0,0,0,0.25),0_12px_28px_-6px_rgba(0,0,0,0.15)] lg:grid-cols-[0.85fr_1.15fr]">
        <div className="hidden flex-col justify-between items-center bg-[#7A1220] border-r border-[#D4AF37]/20 p-8 lg:p-10 text-white lg:flex overflow-y-auto">
          <div className="w-full flex items-center justify-between">
            <p className="text-[11px] font-black uppercase tracking-[0.26em] text-[#D4AF37]">{loginTab === 'staff' ? branchSubtitle(branch) : combinedBranchSubtitle()}</p>
          </div>
          <div className="my-auto flex flex-col items-center justify-center py-6 w-full">
            <div className="relative p-6 sm:p-8 rounded-3xl bg-[#5C0D18] border border-[#D4AF37]/40 shadow-[0_20px_50px_rgba(0,0,0,0.5),0_0_40px_rgba(212,175,55,0.15)] flex items-center justify-center max-w-[280px] w-full aspect-square">
              <img
                src={loginTab === 'staff' ? branchLogo(branch) : BRAND_LOGO}
                alt={BRAND_EN}
                className="w-full h-full object-contain filter drop-shadow-[0_10px_20px_rgba(0,0,0,0.6)]"
              />
            </div>
          </div>
          <div className="w-full flex items-center justify-center gap-2 text-xs font-bold text-[#D4AF37]">
            <ShieldCheck size={15} /> Secure retail workspace
          </div>
        </div>
        <div className="p-5 sm:p-7 lg:p-8 bg-white text-[#111111] overflow-y-auto flex flex-col justify-center">
          {/* Brand */}
          <div className="mb-4 sm:mb-5 flex flex-col items-center text-center lg:items-start lg:text-left">
            {/* Mobile-only logo (since left panel is hidden on mobile) */}
            <div className="mb-3 lg:hidden flex justify-center">
              <div className="w-16 h-16 rounded-2xl bg-[#7A1220] border border-[#D4AF37]/50 p-2 flex items-center justify-center shadow-md">
                <img src={loginTab === 'staff' ? branchLogo(branch) : BRAND_LOGO} alt={BRAND_EN} className="w-full h-full object-contain" />
              </div>
            </div>
            <p className="text-[10px] font-black uppercase tracking-[0.22em] text-[#B48811]">{loginTab === 'staff' ? branchSubtitle(branch) : combinedBranchSubtitle()}</p>
            <h1 className="mt-1 text-2xl sm:text-3xl font-black tracking-tight text-[#7A1220]">{BRAND_EN}</h1>
            {BRAND_TA && BRAND_TA !== BRAND_EN && (
              <p className="mt-0.5 text-xs font-semibold text-[#7A786F]">{BRAND_TA}</p>
            )}
          </div>

          {/* Tab switcher */}
          <div className="mb-4 grid grid-cols-2 gap-1 rounded-xl bg-[#FBFAF6] border border-[#E8D399] p-1">
            <button
              type="button"
              onClick={() => switchTab('staff')}
              className={`flex items-center justify-center gap-1.5 rounded-lg py-2 text-[11px] sm:text-xs font-black uppercase tracking-wide transition-colors cursor-pointer ${
                loginTab === 'staff' ? 'bg-[#7A1220] text-[#D4AF37] shadow' : 'text-[#6B7280] hover:text-[#7A1220]'
              }`}
            >
              <Store size={13} /> {l('Staff POS Login', 'பணியாளர் நுழைவு')}
            </button>
            <button
              type="button"
              onClick={() => switchTab('admin')}
              className={`flex items-center justify-center gap-1.5 rounded-lg py-2 text-[11px] sm:text-xs font-black uppercase tracking-wide transition-colors cursor-pointer ${
                loginTab === 'admin' ? 'bg-[#7A1220] text-[#D4AF37] shadow' : 'text-[#6B7280] hover:text-[#7A1220]'
              }`}
            >
              <ShieldAlert size={13} /> {l('Admin Orchestrator', 'நிர்வாகி')}
            </button>
          </div>

          {/* Server-level error */}
          {error && (
            <div className="bg-red-50 border border-red-200 text-red-600 px-3.5 py-2.5 rounded-xl text-[12px] mb-3.5 flex items-center gap-2">
              <AlertCircle size={14} />
              {error}
            </div>
          )}

          {loginTab === 'staff' ? (
            <form onSubmit={handleStaffSubmit} noValidate className="space-y-3.5">
              <div>
                <label className="mb-1.5 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-[#6B7280]">
                  <Store size={13} />
                  {l('Select Branch', 'கிளையை தேர்ந்தெடுக்கவும்')}
                  <span className="font-black text-red-500">*</span>
                </label>
                <div className="grid grid-cols-3 items-stretch gap-2">
                  {BRANCHES.map(({ key, label }) => (
                    <button
                      key={key}
                      type="button"
                      onClick={() => { setBranch(key); setError('') }}
                      className={`flex min-w-0 flex-col items-center justify-start gap-1.5 rounded-xl border-2 px-2 py-3 text-center transition-colors cursor-pointer ${
                        branch === key
                          ? key === 'pos1'
                            ? 'border-posOne bg-posOne-light text-posOne-dark'
                            : key === 'pos3'
                              ? 'border-posThree bg-posThree-light text-posThree-dark'
                              : 'border-posTwo bg-posTwo-light text-posTwo-dark'
                          : 'border-[#E8D399] bg-[#FBFAF6] text-[#6B7280]'
                      }`}
                    >
                      <span className="w-10 h-10 shrink-0 rounded-lg bg-white border border-black/5 p-1 flex items-center justify-center overflow-hidden">
                        <img src={branchLogo(key)} alt="" className="w-full h-full object-contain" />
                      </span>
                      <span className="flex min-w-0 flex-col items-center">
                        <p className="text-[11px] font-black leading-tight">{label}</p>
                        <p className="mt-0.5 text-[9px] font-semibold leading-tight opacity-80">{BRAND_EN}</p>
                      </span>
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-[#6B7280]">
                  <ShieldCheck size={13} />
                  {l(`${branchShortLabel(branch)} Staff ID`, `${branchShortLabel(branch)} பணியாளர் ஐடி`)}
                  <span className="font-black text-red-500">*</span>
                </label>
                <input
                  type="text"
                  autoComplete="username"
                  placeholder={l(`Enter ${branchShortLabel(branch)} staff ID`, 'பணியாளர் ஐடி')}
                  className="w-full rounded-xl border-2 border-[#E8D399] bg-[#FBFAF6] px-3.5 py-2.5 sm:py-3 text-xs sm:text-sm font-semibold outline-none transition-colors placeholder:text-[#AAA69C] focus:border-[#7A1220] focus:bg-white text-[#111111]"
                  value={staffId}
                  onChange={(e) => { setStaffId(e.target.value); setError('') }}
                  disabled={loading}
                  required
                />
              </div>

              <div>
                <label className="flex items-center gap-1.5 text-[10px] font-bold text-[#6B7280] uppercase tracking-wide mb-1">
                  <Lock size={13} />
                  {l('Password', 'கடவுச்சொல்')}
                  <span className="text-red-500 font-black">*</span>
                </label>
                <div className="relative">
                  <input
                    type={showStaffPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    placeholder={l('Enter password', 'கடவுச்சொல்லை உள்ளிடவும்')}
                    className="w-full rounded-xl border-2 border-[#E8D399] bg-[#FBFAF6] px-3.5 py-2.5 sm:py-3 pr-11 text-xs sm:text-sm font-semibold outline-none transition-colors placeholder:text-[#AAA69C] focus:border-[#7A1220] focus:bg-white text-[#111111]"
                    value={staffPassword}
                    onChange={(e) => { setStaffPassword(e.target.value); setError('') }}
                    disabled={loading}
                    required
                  />
                  <button
                    type="button"
                    onClick={() => setShowStaffPassword(!showStaffPassword)}
                    className="absolute right-2 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-lg text-[#6B7280] hover:bg-[#F9FAFB] hover:text-[#111111] cursor-pointer"
                    aria-label={showStaffPassword ? l('Hide password', 'கடவுச்சொல்லை மறை') : l('Show password', 'கடவுச்சொல்லை காட்டு')}
                  >
                    {showStaffPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="group flex w-full items-center justify-center gap-2 rounded-xl bg-[#7A1220] border border-[#D4AF37] py-3 font-black text-xs sm:text-sm text-[#D4AF37] shadow-lg shadow-black/20 transition-all hover:bg-[#1A1A1A] hover:scale-[1.01] active:scale-[0.99] disabled:opacity-60 cursor-pointer"
              >
                {loading ? (
                  <>
                    <span className="w-3.5 h-3.5 border-2 border-[#D4AF37]/30 border-t-[#D4AF37] rounded-full animate-spin inline-block" />
                    {l('Signing in...', 'உள்நுழைகிறது...')}
                  </>
                ) : (
                  <>
                    <Lock size={14} />
                    {l(`Launch ${branchShortLabel(branch)}`, `${branchShortLabel(branch)} தொடங்கு`)}
                  </>
                )}
              </button>

              <p className="text-center text-[10px] leading-relaxed text-[#888888]">
                {l('Branch POS access with an isolated stock ledger and dedicated invoice sequence.', 'கிளை நுழைவு')}
              </p>
            </form>
          ) : (
            <form onSubmit={handleAdminSubmit} noValidate className="space-y-3.5">
              <div>
                <label className="mb-1 flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-[#6B7280]">
                  <ShieldAlert size={13} />
                  {l('Admin ID', 'நிர்வாகி ஐடி')}
                  <span className="font-black text-red-500">*</span>
                </label>
                <input
                  type="text"
                  autoComplete="username"
                  placeholder={l('Enter admin ID', 'நிர்வாகி ஐடி')}
                  className="w-full rounded-xl border-2 border-[#E8D399] bg-[#FBFAF6] px-3.5 py-2.5 sm:py-3 text-xs sm:text-sm font-semibold outline-none transition-colors placeholder:text-[#AAA69C] focus:border-[#7A1220] focus:bg-white text-[#111111]"
                  value={adminId}
                  onChange={(e) => { setAdminId(e.target.value); setError('') }}
                  disabled={loading}
                  required
                />
              </div>

              <div>
                <label className="flex items-center gap-1.5 text-[10px] font-bold text-[#6B7280] uppercase tracking-wide mb-1">
                  <Lock size={13} />
                  {l('Password', 'கடவுச்சொல்')}
                  <span className="text-red-500 font-black">*</span>
                </label>
                <div className="relative">
                  <input
                    type={showAdminPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    placeholder={l('Enter password', 'கடவுச்சொல்லை உள்ளிடவும்')}
                    className="w-full rounded-xl border-2 border-[#E8D399] bg-[#FBFAF6] px-3.5 py-2.5 sm:py-3 pr-11 text-xs sm:text-sm font-semibold outline-none transition-colors placeholder:text-[#AAA69C] focus:border-[#7A1220] focus:bg-white text-[#111111]"
                    value={adminPassword}
                    onChange={(e) => { setAdminPassword(e.target.value); setError('') }}
                    disabled={loading}
                    required
                  />
                  <button
                    type="button"
                    onClick={() => setShowAdminPassword(!showAdminPassword)}
                    className="absolute right-2 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-lg text-[#6B7280] hover:bg-[#F9FAFB] hover:text-[#111111] cursor-pointer"
                    aria-label={showAdminPassword ? l('Hide password', 'கடவுச்சொல்லை மறை') : l('Show password', 'கடவுச்சொல்லை காட்டு')}
                  >
                    {showAdminPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="group flex w-full items-center justify-center gap-2 rounded-xl bg-[#7A1220] border border-[#D4AF37] py-3 font-black text-xs sm:text-sm text-[#D4AF37] shadow-lg shadow-black/20 transition-all hover:bg-[#1A1A1A] hover:scale-[1.01] active:scale-[0.99] disabled:opacity-60 cursor-pointer"
              >
                {loading ? (
                  <>
                    <span className="w-3.5 h-3.5 border-2 border-[#D4AF37]/30 border-t-[#D4AF37] rounded-full animate-spin inline-block" />
                    {l('Signing in...', 'உள்நுழைகிறது...')}
                  </>
                ) : (
                  <>
                    <ShieldCheck size={14} />
                    {l('Sign In to Admin Orchestrator', 'நிர்வாகியாக நுழைக')}
                  </>
                )}
              </button>

              <p className="text-center text-[10px] leading-relaxed text-[#888888]">
                {l('Superadmin access with cross-branch consolidation and analytics.', 'அனைத்து கிளைகளையும் நிர்வகிக்கவும்.')}
              </p>
            </form>
          )}
        </div>
      </div>
      </div>
      <CenexaFooter />
    </div>
  )
}
