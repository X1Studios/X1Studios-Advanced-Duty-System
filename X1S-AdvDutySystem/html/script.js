const dutyMenu = document.getElementById('dutyMenu')
const supervisorMenu = document.getElementById('supervisorMenu')
const emergencyMenu = document.getElementById('emergencyMenu')
const supervisorList = document.getElementById('supervisorList')
const emptyState = document.getElementById('emptyState')
const officerCount = document.getElementById('officerCount')
const confirmModal = document.getElementById('confirmModal')
const notificationStack = document.getElementById('notificationStack')
const allMenus = [dutyMenu, supervisorMenu, emergencyMenu]

document.documentElement.classList.remove('nui-visible')

let players = []
let pendingForceId = null
let timerInterval = null
let forceRequestTimer = null
let sortState = { key: 'name', direction: 1 }
let activeLocale = {}
let activeNotificationConfig = {
    position: 'top-right',
    duration: 5500,
    maxVisible: 5,
    sound: true
}

function resourceName() {
    return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'x1s-duty'
}

function reportUiError(message) {
    postNui('uiError', { message: String(message || 'Unknown NUI error') }).catch(() => {})
}

function announceReady() {
    postNui('ready').catch(() => window.setTimeout(announceReady, 500))
}

window.addEventListener('error', event => {
    reportUiError(`${event.message} (${event.filename || 'inline'}:${event.lineno || 0})`)
})

window.addEventListener('unhandledrejection', event => {
    reportUiError(event.reason && event.reason.message ? event.reason.message : event.reason)
})

async function postNui(endpoint, payload = {}) {
    const response = await fetch(`https://${resourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload)
    })
    if (!response.ok) {
        throw new Error(`NUI callback ${endpoint} failed with HTTP ${response.status}`)
    }
    return response.json().catch(() => ({}))
}

window.addEventListener('message', event => {
    const data = event.data
    if (!data || typeof data !== 'object') return

    if (data.action === 'close') {
        closeMenu()
        return
    }

    if (data.action === 'openDuty') {
        applyLocale(data.locale)
        applyNotificationConfig(data.notificationConfig)
        populateDepartments(Array.isArray(data.departments) ? data.departments : [])
        showMenu(dutyMenu)
    }

    if (data.action === 'openSupervisor') {
        applyLocale(data.locale)
        applyNotificationConfig(data.notificationConfig)
        players = Array.isArray(data.players)
            ? data.players.map(player => ({ ...player, time: Number(player.time) || 0 }))
            : []
        renderSupervisor()
        startDutyTimers()
        showMenu(supervisorMenu)
    }

    if (data.action === 'openEmergency') {
        applyLocale(data.locale)
        applyNotificationConfig(data.notificationConfig)
        prepareEmergencyForm(data.maxLength)
        showMenu(emergencyMenu)
    }

    if (data.action === 'forceOffResult') {
        handleForceOffResult(data.result)
    }

    if (data.action === 'notify') {
        showNotification(data.notification)
    }
})

function translate(key, fallback = key) {
    return activeLocale[key] || fallback
}

function applyLocale(locale) {
    if (locale && typeof locale === 'object') activeLocale = locale

    document.querySelectorAll('[data-i18n]').forEach(element => {
        const key = element.dataset.i18n
        element.textContent = translate(key, element.textContent)
    })
    document.querySelectorAll('[data-i18n-placeholder]').forEach(element => {
        const key = element.dataset.i18nPlaceholder
        element.placeholder = translate(key, element.placeholder)
    })
}

function applyNotificationConfig(config) {
    if (config && typeof config === 'object') {
        activeNotificationConfig = { ...activeNotificationConfig, ...config }
    }
}

function showUiNotification(type, titleKey, message) {
    showNotification({
        ...activeNotificationConfig,
        type,
        title: translate(titleKey, 'System'),
        message
    })
}

function populateDepartments(departments) {
    const select = document.getElementById('department')
    select.replaceChildren()

    departments
        .slice()
        .sort((a, b) => String(a.label).localeCompare(String(b.label)))
        .forEach(department => {
            const option = document.createElement('option')
            option.value = String(department.value || '')
            option.textContent = String(department.label || department.value || 'Department')
            select.appendChild(option)
        })
}

function showMenu(menu) {
    hideMenus()
    closeModal()
    if (menu !== supervisorMenu) stopDutyTimers()
    menu.hidden = false
    menu.setAttribute('aria-hidden', 'false')
    syncRootVisibility()

    window.setTimeout(() => {
        if (menu === dutyMenu) document.getElementById('department').focus()
        if (menu === supervisorMenu) document.getElementById('searchInput').focus()
        if (menu === emergencyMenu) document.getElementById('emergencyReason').focus()
    }, 0)
}

function hideMenus() {
    for (const menu of allMenus) {
        menu.hidden = true
        menu.setAttribute('aria-hidden', 'true')
    }
}

function closeMenu() {
    hideMenus()
    closeModal()
    stopDutyTimers()
    clearForceRequest()
    syncRootVisibility()
    postNui('close').catch(() => {})
}

async function confirmDuty() {
    const button = document.getElementById('confirmDuty')
    const payload = {
        name: document.getElementById('name').value.trim(),
        callsign: document.getElementById('callsign').value.trim(),
        rank: document.getElementById('rank').value.trim(),
        department: document.getElementById('department').value
    }

    if (!payload.name || !payload.callsign || !payload.rank || !payload.department) {
        showUiNotification('warning', 'notification_duty', translate('missing_fields', 'Complete every field before going on duty.'))
        return
    }

    button.disabled = true
    button.textContent = `${translate('confirm', 'Confirm')}...`
    try {
        const result = await postNui('goOnDuty', payload)
        if (result && result.ok === false) {
            showUiNotification('error', 'notification_duty', result.error || translate('unable_duty_request', 'Unable to submit the duty request.'))
            return
        }
        closeMenu()
    } catch (_) {
        showUiNotification('error', 'notification_duty', translate('unable_contact', 'Unable to contact the duty system.'))
    } finally {
        button.disabled = false
        button.textContent = translate('confirm', 'Confirm')
    }
}

function filteredPlayers() {
    const query = document.getElementById('searchInput').value.trim().toLowerCase()
    const filtered = !query ? [...players] : players.filter(player =>
        [player.name, player.callsign, player.rank, player.department]
            .some(value => String(value || '').toLowerCase().includes(query))
    )

    return filtered.sort((a, b) => {
        const aValue = sortState.key === 'time' ? Number(a.time) : String(a[sortState.key] || '').toLowerCase()
        const bValue = sortState.key === 'time' ? Number(b.time) : String(b[sortState.key] || '').toLowerCase()
        if (typeof aValue === 'number') return (aValue - bValue) * sortState.direction
        return aValue.localeCompare(bValue) * sortState.direction
    })
}

function renderSupervisor() {
    const visiblePlayers = filteredPlayers()
    supervisorList.replaceChildren()

    for (const player of visiblePlayers) {
        const row = document.createElement('tr')
        row.dataset.playerId = String(player.id)

        for (const key of ['name', 'callsign', 'rank', 'department']) {
            const cell = document.createElement('td')
            cell.textContent = String(player[key] || '-')
            cell.title = cell.textContent
            row.appendChild(cell)
        }

        const status = document.createElement('td')
        status.className = 'status duty-time'
        status.dataset.id = String(player.id)
        status.textContent = translate('on_time', 'On %s').replace('%s', formatTime(player.time))
        row.appendChild(status)

        const action = document.createElement('td')
        action.className = 'action-cell'
        const offButton = document.createElement('button')
        offButton.type = 'button'
        offButton.className = 'danger'
        offButton.textContent = translate('force_off', 'Force Off')
        offButton.addEventListener('click', () => openConfirm(player.id))
        action.appendChild(offButton)
        row.appendChild(action)

        supervisorList.appendChild(row)
    }

    officerCount.textContent = players.length === 1
        ? translate('officer_count_one', '1 officer')
        : translate('officer_count', '%s officers').replace('%s', players.length)
    emptyState.hidden = visiblePlayers.length > 0
}

function setSort(key) {
    sortState = sortState.key === key
        ? { key, direction: sortState.direction * -1 }
        : { key, direction: 1 }
    updateSortIndicators()
    renderSupervisor()
}

function updateSortIndicators() {
    document.querySelectorAll('[data-sort]').forEach(button => {
        const isActive = button.dataset.sort === sortState.key
        const heading = button.closest('th')
        const indicator = button.querySelector('.sort-indicator')

        heading.setAttribute(
            'aria-sort',
            isActive ? (sortState.direction === 1 ? 'ascending' : 'descending') : 'none'
        )
        indicator.textContent = isActive ? (sortState.direction === 1 ? '^' : 'v') : '-'
    })
}

function startDutyTimers() {
    stopDutyTimers()
    timerInterval = window.setInterval(() => {
        for (const player of players) player.time += 1
        document.querySelectorAll('.duty-time').forEach(element => {
            const player = players.find(item => String(item.id) === element.dataset.id)
            if (player) element.textContent = translate('on_time', 'On %s').replace('%s', formatTime(player.time))
        })
    }, 1000)
}

function stopDutyTimers() {
    if (timerInterval !== null) {
        window.clearInterval(timerInterval)
        timerInterval = null
    }
}

function openConfirm(id) {
    pendingForceId = Number(id)
    confirmModal.hidden = false
    confirmModal.setAttribute('aria-hidden', 'false')
}

function closeModal() {
    confirmModal.hidden = true
    confirmModal.setAttribute('aria-hidden', 'true')
    pendingForceId = null
}

async function confirmForceOff() {
    if (!Number.isInteger(pendingForceId)) return
    const target = pendingForceId
    const button = document.getElementById('confirmForce')
    button.disabled = true
    button.textContent = `${translate('force_off', 'Force Off')}...`

    try {
        const result = await postNui('forceOff', { id: target })
        if (result && result.ok === false) {
            throw new Error(result.error || 'Unable to send the force-off request.')
        }

        window.clearTimeout(forceRequestTimer)
        forceRequestTimer = window.setTimeout(() => {
            resetForceButton()
            showUiNotification('warning', 'notification_duty', translate('server_no_response', 'The server did not respond. Please try again.'))
        }, 8000)
    } catch (_) {
        resetForceButton()
        showUiNotification('error', 'notification_duty', translate('unable_force_off', 'Unable to send the force-off request.'))
    }
}

function handleForceOffResult(result) {
    if (!result || typeof result !== 'object') return

    clearForceRequest()
    if (result.ok) {
        players = players.filter(player => Number(player.id) !== Number(result.target))
        closeModal()
        renderSupervisor()
    }

    showUiNotification(
        result.ok ? 'success' : 'error',
        'notification_duty',
        result.message || (result.ok ? translate('force_off', 'Force Off') : translate('force_off_denied_generic', 'Force-off request denied.'))
    )
}

function resetForceButton() {
    const button = document.getElementById('confirmForce')
    button.disabled = false
    button.textContent = translate('force_off', 'Force Off')
}

function clearForceRequest() {
    window.clearTimeout(forceRequestTimer)
    forceRequestTimer = null
    resetForceButton()
}

function formatTime(totalSeconds) {
    const seconds = Math.max(0, Math.floor(Number(totalSeconds) || 0))
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const remaining = seconds % 60
    return hours > 0
        ? `${hours}h ${minutes}m ${remaining}s`
        : `${minutes}m ${remaining}s`
}

function prepareEmergencyForm(maxLength) {
    const textarea = document.getElementById('emergencyReason')
    const limit = Math.min(1000, Math.max(32, Number(maxLength) || 256))
    textarea.maxLength = limit
    textarea.value = ''
    document.getElementById('emergencyCharacterLimit').textContent = String(limit)
    updateEmergencyCharacterCount()
}

function updateEmergencyCharacterCount() {
    document.getElementById('emergencyCharacterCount').textContent = String(
        document.getElementById('emergencyReason').value.length
    )
}

async function submitEmergency() {
    const textarea = document.getElementById('emergencyReason')
    const button = document.getElementById('submitEmergency')
    const reason = textarea.value.trim()

    if (!reason) {
        showUiNotification('warning', 'notification_dispatch', translate('missing_report', 'Enter details about the emergency before sending the call.'))
        textarea.focus()
        return
    }

    button.disabled = true
    button.textContent = `${translate('send_emergency', 'Send 911 Call')}...`
    try {
        const result = await postNui('submitEmergency', { reason })
        if (result && result.ok === false) {
            showUiNotification('error', 'notification_dispatch', result.error || translate('invalid_emergency', 'The emergency call contained invalid information.'))
            return
        }
        closeMenu()
    } catch (_) {
        showUiNotification('error', 'notification_dispatch', translate('invalid_emergency', 'The emergency call contained invalid information.'))
    } finally {
        button.disabled = false
        button.textContent = translate('send_emergency', 'Send 911 Call')
    }
}

function syncRootVisibility() {
    const hasVisibleMenu = allMenus.some(menu => !menu.hidden)
    const hasNotifications = notificationStack.childElementCount > 0
    document.documentElement.classList.toggle('nui-visible', hasVisibleMenu || hasNotifications)
}

function showNotification(data) {
    if (!data || typeof data !== 'object') return

    const allowedTypes = new Set(['info', 'success', 'warning', 'error', 'dispatch', 'panic'])
    const allowedPositions = new Set(['top-right', 'top-left', 'bottom-right', 'bottom-left'])
    const type = allowedTypes.has(data.type) ? data.type : 'info'
    const position = allowedPositions.has(data.position) ? data.position : 'top-right'
    const duration = Math.min(30000, Math.max(1500, Number(data.duration) || 5500))
    const maxVisible = Math.min(10, Math.max(1, Number(data.maxVisible) || 5))

    notificationStack.className = `notification-stack notification-stack--${position}`
    while (notificationStack.childElementCount >= maxVisible) {
        notificationStack.firstElementChild.remove()
    }

    const notification = document.createElement('article')
    notification.className = `notification notification--${type}`

    const icon = document.createElement('span')
    icon.className = 'notification__icon'
    icon.textContent = type === 'success' ? '+' : type === 'warning' ? '!' : type === 'info' ? 'i' : 'X'

    const title = document.createElement('h2')
    title.className = 'notification__title'
    title.textContent = String(data.title || translate('notification_system', 'System'))

    const message = document.createElement('p')
    message.className = 'notification__message'
    message.textContent = String(data.message || '')

    const progress = document.createElement('span')
    progress.className = 'notification__progress'
    progress.style.animationDuration = `${duration}ms`

    notification.append(icon, title, message, progress)
    notificationStack.appendChild(notification)
    syncRootVisibility()

    if (data.sound) playNotificationSound(type)
    window.setTimeout(() => removeNotification(notification), duration)
}

function removeNotification(notification) {
    if (!notification.isConnected) return
    notification.style.animation = 'notification-out 160ms ease-in forwards'
    window.setTimeout(() => {
        notification.remove()
        syncRootVisibility()
    }, 170)
}

function playNotificationSound(type) {
    try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext
        if (!AudioContextClass) return
        const context = new AudioContextClass()
        const oscillator = context.createOscillator()
        const gain = context.createGain()
        oscillator.frequency.value = type === 'panic' ? 760 : type === 'dispatch' ? 620 : 520
        gain.gain.setValueAtTime(0.035, context.currentTime)
        gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.16)
        oscillator.connect(gain)
        gain.connect(context.destination)
        oscillator.start()
        oscillator.stop(context.currentTime + 0.16)
        oscillator.addEventListener('ended', () => context.close())
    } catch (_) {
        // Audio is optional and may be blocked by the embedded browser.
    }
}

document.getElementById('cancelDuty').addEventListener('click', closeMenu)
document.getElementById('confirmDuty').addEventListener('click', confirmDuty)
document.getElementById('closeSupervisor').addEventListener('click', closeMenu)
document.getElementById('cancelEmergency').addEventListener('click', closeMenu)
document.getElementById('submitEmergency').addEventListener('click', submitEmergency)
document.getElementById('emergencyReason').addEventListener('input', updateEmergencyCharacterCount)
document.getElementById('cancelForce').addEventListener('click', closeModal)
document.getElementById('confirmForce').addEventListener('click', confirmForceOff)
document.getElementById('searchInput').addEventListener('input', renderSupervisor)
document.querySelectorAll('[data-sort]').forEach(button => {
    button.addEventListener('click', () => setSort(button.dataset.sort))
})

document.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return
    if (!confirmModal.hidden) closeModal()
    else closeMenu()
})

announceReady()
