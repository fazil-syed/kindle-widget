// Kindle Reading Progress widget for Übersicht
// - shows Kindle's own numbers: book, author, progress percent, bar
// - drag to move (position persists across restarts)
// - click to open the Kindle app (it resumes at your furthest-read page)

import { run } from "uebersicht"

export const command = `zsh @KINDLE_HOME@/widget-data.sh 2>/dev/null`
export const refreshFrequency = 15000

export const className = `
  .kindle-widget {
    position: fixed;
    font-family: -apple-system, "SF Pro Text", Helvetica;
    color: #f5f5f7;
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-width: 260px;
  }
  .kindle-card {
    background: rgba(22, 22, 25, 0.72);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    border: 0.5px solid rgba(255,255,255,0.12);
    border-radius: 16px;
    padding: 16px 18px 14px;
    box-shadow: 0 8px 30px rgba(0,0,0,0.35);
    -webkit-user-select: none;
    user-select: none;
    cursor: pointer;
  }
  .kindle-card:hover {
    border-color: rgba(255,255,255,0.25);
  }
  .kindle-label {
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: rgba(255,255,255,0.45);
    margin-bottom: 6px;
  }
  .kindle-title {
    font-size: 14px;
    font-weight: 600;
    line-height: 1.25;
    margin-bottom: 2px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 300px;
  }
  .kindle-author {
    font-size: 11px;
    color: rgba(255,255,255,0.55);
    margin-bottom: 10px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 300px;
  }
  .kindle-page {
    display: flex;
    align-items: baseline;
    margin-bottom: 10px;
  }
  .kindle-page .of {
    font-size: 12px;
    color: rgba(255,255,255,0.5);
  }
  .kindle-page .approx {
    font-size: 13px;
    color: rgba(255,255,255,0.5);
  }
  .kindle-page .num {
    font-size: 40px;
    font-weight: 300;
    line-height: 1;
    letter-spacing: -0.02em;
  }
  .kindle-track {
    height: 4px;
    background: rgba(255,255,255,0.14);
    border-radius: 2px;
    overflow: hidden;
    margin-bottom: 6px;
  }
  }
  .kindle-fill {
    height: 100%;
    background: linear-gradient(90deg, #ff9a3c, #ffb56b);
    border-radius: 2px;
  }
  .kindle-sub {
    font-size: 10px;
    color: rgba(255,255,255,0.42);
  }
  .kindle-empty {
    background: rgba(22,22,25,0.72);
    border: 0.5px solid rgba(255,255,255,0.12);
    border-radius: 16px;
    padding: 14px 18px;
    font-size: 12px;
    color: rgba(255,255,255,0.6);
    max-width: 320px;
    word-break: break-word;
    cursor: pointer;
  }
`

// Drag anywhere to reposition (saved, persists). A click without drag
// opens the Kindle app, which resumes at your furthest-read position.
const onTapOrDrag = (e) => {
  const widget = e.currentTarget.parentElement
  if (!widget) return
  e.preventDefault()
  const startX = e.clientX
  const startY = e.clientY
  const rect = widget.getBoundingClientRect()
  const offX = startX - rect.left
  const offY = startY - rect.top
  let moved = false

  widget.style.opacity = "0.85"
  widget.style.transform = "none"

  const move = (ev) => {
    const dx = ev.clientX - startX
    const dy = ev.clientY - startY
    if (!moved && Math.hypot(dx, dy) > 4) moved = true
    if (!moved) return
    const w = window.innerWidth
    const h = window.innerHeight
    const l = Math.min(Math.max(ev.clientX - offX, 0), Math.max(w - 40, 40))
    const t = Math.min(Math.max(ev.clientY - offY, 0), Math.max(h - 20, 20))
    widget.style.left = l + "px"
    widget.style.top = t + "px"
  }

  const up = () => {
    window.removeEventListener("mousemove", move)
    window.removeEventListener("mouseup", up)
    widget.style.opacity = ""

    if (!moved) {
      // Treat as click → open Kindle, which resumes the last-read book/page.
      run(`open -a "Kindle"`)
      return
    }

    const w = window.innerWidth
    const h = window.innerHeight
    const x = parseFloat(widget.style.left) / w
    const y = parseFloat(widget.style.top) / h
    if (!isNaN(x) && !isNaN(y)) {
      run(
        `mkdir -p "$HOME/Library/Application Support/KindleWidget" && ` +
        `printf '{"x":${x.toFixed(4)},"y":${y.toFixed(4)}}' > "$HOME/Library/Application Support/KindleWidget/position.json"`
      )
    }
  }

  window.addEventListener("mousemove", move)
  window.addEventListener("mouseup", up)
}

const Book = (b) => {
  const hasPage = b.currentPage != null && b.printPages != null
  return (
    <div className="kindle-card" onMouseDown={onTapOrDrag}>
      <div className="kindle-label">Now Reading · Kindle</div>
      <div className="kindle-title">{b.title}</div>
      <div className="kindle-author">{b.author}</div>
      <div className="kindle-page">
        <span className="num">{b.percent.toFixed(1)}%</span>
      </div>
      <div className="kindle-track">
        <div className="kindle-fill" style={{ width: `${b.percent}%` }} />
      </div>
      <div className="kindle-sub">
        {hasPage ? `≈ page ${b.currentPage} of ${b.printPages} · ` : ""}
        click to open · drag to move
      </div>
    </div>
  )
}

const rootStyle = (pos) => {
  if (pos && typeof pos.x === "number" && typeof pos.y === "number") {
    return { left: (pos.x * window.innerWidth) + "px", top: (pos.y * window.innerHeight) + "px" }
  }
  return { left: "50%", top: "50%", transform: "translate(-50%, -50%)" }
}

export const render = ({ output, error }) => {
  let data = null
  try { data = JSON.parse(output) } catch (e) {}
  // Accept both {pos, books} and a bare array (older script format)
  const books = Array.isArray(data) ? data : (data && data.books)
  const pos = data && !Array.isArray(data) ? data.pos : null

  const card = (
    error ? (
      <div className="kindle-empty" onMouseDown={onTapOrDrag}>Kindle widget error: {String(error)}</div>
    ) : (
      !books || books.length === 0 ? (
        <div className="kindle-empty" onMouseDown={onTapOrDrag}>
          {output ? `Bad output: ${String(output).slice(0, 160)}` : "No reading data found"}
        </div>
      ) : (
        books.map((b, i) => <Book key={i} {...b} />)
      )
    )
  )

  return (
    <div className="kindle-widget" style={rootStyle(pos)}>
      {card}
    </div>
  )
}
