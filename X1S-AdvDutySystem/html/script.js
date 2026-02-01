let dutyTimers = {}
let timerInterval = null
let pendingForceId = null

/* =========================
   NUI LISTENERS
========================= */
window.addEventListener('message', function (e) {
    const data = e.data

    if (data.action === 'openDuty') {
        const deptSelect = document.getElementById('department')
        deptSelect.innerHTML = ''

        data.departments.forEach(d => {
            const opt = document.createElement('option')
            opt.value = d.value      // 🔥 MUST BE THE KEY
            opt.textContent = d.label
            deptSelect.appendChild(opt)
        })

        showMenu('dutyMenu')
    }

    if (data.action === 'openSupervisor') {
        renderSupervisor(data.players)
        showMenu('supervisorMenu')
    }
})

/* =========================
   MENUS
========================= */
function showMenu(id) {
    document.getElementById(id).style.display = 'block'
}

function closeMenu() {
    document.getElementById('dutyMenu').style.display = 'none'
    document.getElementById('supervisorMenu').style.display = 'none'
    closeModal()

    if (timerInterval) {
        clearInterval(timerInterval)
        timerInterval = null
    }

    fetch(`https://${GetParentResourceName()}/close`, { method: 'POST' })
}

/* ESC KEY CLOSE */
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') closeMenu()
})

/* =========================
   DUTY
========================= */
function confirmDuty() {
    const name = document.getElementById('name').value.trim()
    const callsign = document.getElementById('callsign').value.trim()
    const rank = document.getElementById('rank').value.trim()
    const department = document.getElementById('department').value

    if (!name || !callsign || !rank || !department) {
        return
    }

    fetch(`https://${GetParentResourceName()}/goOnDuty`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ department, name, callsign, rank })
    })

    closeMenu()
}

/* =========================
   SUPERVISOR
========================= */
function renderSupervisor(players) {
    const body = document.getElementById('supervisorList')
    body.innerHTML = ''
    dutyTimers = {}

    players.forEach(p => {
        dutyTimers[p.id] = p.time

        const tr = document.createElement('tr')
        tr.innerHTML = `
            <td>${escapeHtml(p.name)}</td>
            <td>${escapeHtml(p.callsign)}</td>
            <td>${escapeHtml(p.rank)}</td>
            <td>${escapeHtml(p.department)}</td>
            <td class="duty-time" data-id="${p.id}">${formatTime(p.time)}</td>
            <td>
                <button class="danger" onclick="openConfirm(${p.id})">Off</button>
            </td>
        `
        body.appendChild(tr)
    })

    startDutyTimers()
}

function startDutyTimers() {
    if (timerInterval) clearInterval(timerInterval)

    timerInterval = setInterval(() => {
        document.querySelectorAll('.duty-time').forEach(el => {
            const id = el.dataset.id
            if (dutyTimers[id] !== undefined) {
                dutyTimers[id]++
                el.textContent = formatTime(dutyTimers[id])
            }
        })
    }, 1000)
}

/* =========================
   FORCE OFF CONFIRM MODAL
========================= */
function openConfirm(id) {
    pendingForceId = id
    document.getElementById('confirmModal').style.display = 'flex'
}

function closeModal() {
    document.getElementById('confirmModal').style.display = 'none'
    pendingForceId = null
}

function confirmModalAction() {
    if (!pendingForceId) return

    fetch(`https://${GetParentResourceName()}/forceOff`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: pendingForceId })
    })
}

/* =========================
   UTILS
========================= */
function formatTime(sec) {
    const h = Math.floor(sec / 3600)
    const m = Math.floor((sec % 3600) / 60)
    const s = sec % 60
    return `${h}h ${m}m ${s}s`
}

function escapeHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;')
}
