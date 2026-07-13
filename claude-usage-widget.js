// ============================================================
//  Claude Usage — Scriptable Widget
//  แสดง % session / % week / % Fable จาก claude-usage API
//  ถ้ารอบไหน Fable ไม่มา (โดน rate limit) จะโชว์ "rate limit"
//
//  รองรับหลายขนาด:
//   • Lock Screen วงกลม (accessoryCircular) = "ช่องเดียว" โชว์ session
//   • Lock Screen แถบ (accessoryRectangular) = โชว์ทั้ง 3 ค่า
//   • Lock Screen บรรทัด (accessoryInline)
//   • Home Screen Small/Medium
//
//  วิธีวาง Lock Screen: แตะค้าง Lock Screen > Customize > Lock Screen
//   > แตะช่อง widget > Scriptable > เลือก script นี้
// ============================================================

// ── ตั้งค่า ──────────────────────────────────────────────
const API_URL = "https://claude-usage.sasis.site/usage"
const API_KEY = "YOUR_API_KEY_HERE"  // ← ใส่ค่าจาก .env (X-API-Key)

// สีพื้นหลัง widget บนหน้า Home (hex) — ธีม Anthropic: ครีม/ขาว
// เปลี่ยนได้ที่นี่ หรือใส่ hex ในช่อง "Parameter" ตอน Edit Widget เพื่อกำหนดเป็นราย widget
// (Lock Screen ตั้งพื้นหลังไม่ได้ — iOS คุมเอง)
const BG_COLOR = "#F0EEE6"
// ────────────────────────────────────────────────────────

async function loadUsage() {
  const req = new Request(API_URL)
  req.headers = { "X-API-Key": API_KEY }
  req.timeoutInterval = 15
  return await req.loadJSON()
}

// ── ธีม Anthropic (ส้ม/ขาว) ───────────────────────────────
const ORANGE = new Color("#CC785C")  // Claude clay orange (ค่าปกติ)
const HIGH   = new Color("#BD4B2F")  // ส้มเข้ม/แดงดิน เตือนใกล้เต็ม (>=85%)
const INK    = new Color("#28261B")  // ตัวอักษรหลัก
const MUTED  = new Color("#8A8981")  // ตัวอักษรรอง / no data
const RL     = MUTED                 // rate limit = โทนเทาอบอุ่น

function levelColor(pct) {
  if (pct == null) return MUTED
  if (pct >= 85) return HIGH
  return ORANGE
}

// คืน {text, color, big} สำหรับค่า Fable
function fableView(data) {
  if (data.fable_status === "rate_limited") return { text: "rate limit", color: RL, big: false }
  if (data.fable_pct == null) return { text: "—", color: MUTED, big: true }
  return { text: `${data.fable_pct}%`, color: levelColor(data.fable_pct), big: true }
}

// ── วาดวงกลม gauge สำหรับ Lock Screen (ช่องเดียว) ─────────
function gaugeImage(pct, size) {
  const val = pct == null ? 0 : Math.max(0, Math.min(100, pct))
  const ctx = new DrawContext()
  ctx.size = new Size(size, size)
  ctx.opaque = false
  ctx.respectScreenScale = true
  const lw = size * 0.13
  const r = (size - lw) / 2
  const cx = size / 2, cy = size / 2

  ctx.setStrokeColor(new Color("#ffffff", 0.25))
  ctx.setLineWidth(lw)
  const track = new Path()
  track.addEllipse(new Rect(lw / 2, lw / 2, size - lw, size - lw))
  ctx.addPath(track); ctx.strokePath()

  ctx.setFillColor(pct == null ? MUTED : new Color("#ffffff"))
  const steps = Math.round((val / 100) * 90)
  for (let i = 0; i < steps; i++) {
    const a = (-90 + i * 4) * Math.PI / 180
    const x = cx + r * Math.cos(a), y = cy + r * Math.sin(a)
    const dot = new Path()
    dot.addEllipse(new Rect(x - lw / 2, y - lw / 2, lw, lw))
    ctx.addPath(dot); ctx.fillPath()
  }
  ctx.setTextAlignedCenter()
  ctx.setTextColor(new Color("#ffffff"))
  ctx.setFont(Font.boldSystemFont(size * 0.3))
  ctx.drawTextInRect(pct == null ? "—" : `${val}`,
    new Rect(0, cy - size * 0.22, size, size * 0.4))
  return ctx.getImage()
}

function buildCircular(data, err) {
  const w = new ListWidget()
  const img = w.addImage(gaugeImage(err ? null : data.session_pct, 100))
  img.imageSize = new Size(52, 52)
  img.centerAlignImage()
  return w
}

function buildRectangular(data, err) {
  const w = new ListWidget()
  if (err) { w.addText("Claude: error"); return w }
  const t = w.addText("Claude Usage")
  t.font = Font.semiboldSystemFont(12)
  w.addSpacer(2)
  const fv = fableView(data)
  w.addText(`Session  ${data.session_pct ?? "—"}%`).font = Font.systemFont(12)
  w.addText(`Week      ${data.week_pct ?? "—"}%`).font = Font.systemFont(12)
  w.addText(`Fable     ${fv.text}`).font = Font.systemFont(12)
  return w
}

function buildInline(data, err) {
  const w = new ListWidget()
  if (err) { w.addText("Claude: error"); return w }
  const fv = fableView(data)
  const f = data.fable_status === "rate_limited" ? "RL" : (data.fable_pct ?? "—") + "%"
  w.addText(`Claude S${data.session_pct ?? "—"}% W${data.week_pct ?? "—"}% F${f}`)
  return w
}

// ── Home Screen ───────────────────────────────────────────
function addMetric(stack, label, valueText, color, big) {
  const row = stack.addStack()
  row.centerAlignContent()
  const name = row.addText(label)
  name.textColor = INK
  name.font = Font.mediumSystemFont(14)
  row.addSpacer()
  const val = row.addText(valueText)
  val.textColor = color
  val.font = big ? Font.boldSystemFont(22) : Font.semiboldSystemFont(15)
}

function resolveBg() {
  // ช่อง Parameter (ตอน Edit Widget) มาก่อน ถ้าเป็น hex ที่ถูกต้อง
  const p = (args.widgetParameter || "").trim()
  const hex = /^#?[0-9a-fA-F]{6}$/.test(p) ? (p[0] === "#" ? p : "#" + p) : BG_COLOR
  return new Color(hex)
}

function buildHome(data, err) {
  const w = new ListWidget()
  w.backgroundColor = resolveBg()
  w.setPadding(14, 16, 14, 16)

  const header = w.addStack()
  header.centerAlignContent()
  const dot = header.addText("● ")
  dot.textColor = err ? HIGH : ORANGE
  dot.font = Font.systemFont(10)
  const title = header.addText("Claude Usage")
  title.textColor = MUTED
  title.font = Font.semiboldSystemFont(12)
  w.addSpacer(8)

  if (err) {
    const e = w.addText("โหลดข้อมูลไม่ได้")
    e.textColor = HIGH
    e.font = Font.mediumSystemFont(14)
    return w
  }

  const s = data.session_pct, k = data.week_pct
  const fv = fableView(data)
  addMetric(w, "Session", s == null ? "—" : `${s}%`, levelColor(s), true)
  w.addSpacer(6)
  addMetric(w, "Week", k == null ? "—" : `${k}%`, levelColor(k), true)
  w.addSpacer(6)
  addMetric(w, "Fable", fv.text, fv.color, fv.big)
  w.addSpacer()

  let stamp = ""
  if (data.updated) {
    const d = new Date(data.updated)
    stamp = "updated " +
      d.toLocaleTimeString("th-TH", { hour: "2-digit", minute: "2-digit" })
  }
  const foot = w.addText(stamp)
  foot.textColor = MUTED
  foot.font = Font.systemFont(9)
  return w
}

// ── main ──────────────────────────────────────────────────
let data = null, err = null
try { data = await loadUsage() } catch (e) { err = e.message || String(e) }

let widget
switch (config.widgetFamily) {
  case "accessoryCircular":    widget = buildCircular(data, err); break
  case "accessoryRectangular": widget = buildRectangular(data, err); break
  case "accessoryInline":      widget = buildInline(data, err); break
  default:                     widget = buildHome(data, err)
}

if (config.runsInWidget) {
  Script.setWidget(widget)
} else {
  await widget.presentSmall()
}
Script.complete()
