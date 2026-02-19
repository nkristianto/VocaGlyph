import { useState, useEffect, useCallback, useRef } from 'react';
import './App.css';
import { GetStatus, GetLaunchAtLogin, SetLaunchAtLogin, OpenSystemSettings, GetConfig, SetModel, SetLanguage, GetHotkey, SetHotkey } from '../wailsjs/go/main/App';
import { EventsOn, WindowSetPosition } from '../wailsjs/runtime/runtime';

// App state drives .vtt-state-* class on root — controls all visual states
const APP_STATES = {
    IDLE: 'idle',
    RECORDING: 'recording',
    PROCESSING: 'processing',
};

// ── RecordingHUD ─────────────────────────────────────────
// Floating pill shown while recording is active.
function RecordingHUD({ elapsedSecs }) {
    const mm = String(Math.floor(elapsedSecs / 60)).padStart(1, '0');
    const ss = String(elapsedSecs % 60).padStart(2, '0');

    return (
        <div className="vtt-hud" role="status" aria-label="Recording in progress">
            <span className="vtt-hud__dot" />
            <div className="vtt-hud__wave" aria-hidden="true">
                <span className="vtt-hud__bar" />
                <span className="vtt-hud__bar" />
                <span className="vtt-hud__bar" />
                <span className="vtt-hud__bar" />
                <span className="vtt-hud__bar" />
                <span className="vtt-hud__bar" />
            </div>
            <span className="vtt-hud__label">Rec</span>
            <span id="vtt-hud-timer" className="vtt-hud__timer">{mm}:{ss}</span>
        </div>
    );
}

// ── TranscriptionOverlay ──────────────────────────────────
// Shows transcribed text with a 1.5s draining progress bar.
function TranscriptionOverlay({ text }) {
    return (
        <div
            id="vtt-overlay"
            className="vtt-overlay"
            role="status"
            aria-live="polite"
            aria-atomic="true"
        >
            <div className="vtt-overlay__header">
                <span className="vtt-overlay__check">✓</span>
                <span className="vtt-overlay__label">Transcribed</span>
            </div>
            <p id="vtt-overlay-text" className="vtt-overlay__text">{text}</p>
            <div className="vtt-overlay__progress">
                <div className="vtt-overlay__progress-bar" />
            </div>
        </div>
    );
}

// ── ClipboardToast ────────────────────────────────────────
// Brief amber banner when paste falls back to clipboard.
function ClipboardToast() {
    return (
        <div id="vtt-toast" className="vtt-toast" role="alert">
            <span className="vtt-toast__icon">📋</span>
            <span className="vtt-toast__text">Copied to clipboard — paste with <kbd>⌘V</kbd></span>
        </div>
    );
}

// ── SettingsPanel ─────────────────────────────────────────
// Model picker + language selector, collapsed below the divider.
const MODELS = ['tiny', 'base', 'small'];
const LANGUAGES = [
    { value: 'en', label: 'English' },
    { value: 'auto', label: 'Auto-detect' },
    { value: 'es', label: 'Spanish' },
    { value: 'fr', label: 'French' },
    { value: 'de', label: 'German' },
    { value: 'ja', label: 'Japanese' },
];

function SettingsPanel({ config, onModelChange, onLanguageChange, onHotkeyChange }) {
    return (
        <div className="vtt-settings">
            <div className="vtt-settings__row">
                <span className="vtt-settings__label">Hotkey</span>
                <HotkeyCapture current={config.hotkey} onChange={onHotkeyChange} />
            </div>
            <div className="vtt-settings__row">
                <span className="vtt-settings__label">Model</span>
                <div className="vtt-model-picker" role="group" aria-label="Model size">
                    {MODELS.map((m) => (
                        <button
                            key={m}
                            id={`vtt-model-${m}`}
                            className={`vtt-model-btn${config.model === m ? ' vtt-model-btn--active' : ''}`}
                            onClick={() => onModelChange(m)}
                            aria-pressed={config.model === m}
                        >
                            {m}
                        </button>
                    ))}
                </div>
            </div>
            <div className="vtt-settings__row">
                <span className="vtt-settings__label">Language</span>
                <select
                    id="vtt-language-select"
                    className="vtt-lang-select"
                    value={config.language}
                    onChange={(e) => onLanguageChange(e.target.value)}
                    aria-label="Transcription language"
                >
                    {LANGUAGES.map((l) => (
                        <option key={l.value} value={l.value}>{l.label}</option>
                    ))}
                </select>
            </div>
        </div>
    );
}

// ── HotkeyCapture ─────────────────────────────────────────
// Two modes:
//   1. Keydown capture (default) — click badge, press keys
//   2. Text input fallback — for combos macOS intercepts (e.g. ⌃Space)
//      click "type it" to enter a text field like "ctrl+space"
function HotkeyCapture({ current, onChange }) {
    const [mode, setMode] = useState('idle'); // 'idle' | 'capture' | 'text'
    const [textVal, setTextVal] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);
    const textRef = useRef(null);

    // Format a combo string ("ctrl+space") to a symbol string ("⌃Space")
    const format = useCallback((combo) => {
        if (!combo) return '⌃Space';
        const modSymbols = { ctrl: '⌃', control: '⌃', option: '⌥', alt: '⌥', shift: '⇧', cmd: '⌘', command: '⌘' };
        const keyLabels = { space: 'Space', tab: 'Tab', return: 'Return', enter: 'Return' };
        const parts = combo.toLowerCase().split('+');
        const key = parts[parts.length - 1];
        const mods = parts.slice(0, -1);
        return mods.map(m => modSymbols[m] || m).join('') + (keyLabels[key] || key.toUpperCase());
    }, []);

    const applyCombo = useCallback((combo) => {
        setErrorMsg(null); // clear any previous error when trying
        onChange(combo)
            .then(() => { setMode('idle'); })
            .catch(() => {
                // Stay in capture mode so user can immediately press another key.
                // Show a concise inline error; add macOS hint only for ctrl+space.
                const isSpace = combo.includes('space');
                setErrorMsg(
                    `"${format(combo)}" is taken.` +
                    (isSpace ? ' Free it in System Preferences → Keyboard → Shortcuts.' : ' Try a different combo.')
                );
                setMode('capture'); // keep listening for next attempt
            });
    }, [onChange, format]);

    // ── keydown capture mode ──────────────────────────────
    const handleKeyDown = useCallback((e) => {
        if (mode !== 'capture') return;
        e.preventDefault();
        e.stopPropagation();

        if (e.key === 'Escape') { setMode('idle'); setErrorMsg(null); return; }
        if (['Control', 'Meta', 'Alt', 'Shift'].includes(e.key)) return;

        const parts = [];
        if (e.ctrlKey) parts.push('ctrl');
        if (e.altKey) parts.push('option');
        if (e.shiftKey) parts.push('shift');
        if (e.metaKey) parts.push('cmd');
        if (parts.length === 0) return;

        const keyName = e.code === 'Space' ? 'space'
            : e.key === 'Tab' ? 'tab'
                : (e.key === 'Enter' || e.key === 'Return') ? 'return'
                    : e.key.toLowerCase();
        parts.push(keyName);

        setMode('idle');
        applyCombo(parts.join('+'));
    }, [mode, applyCombo]);

    useEffect(() => {
        if (mode === 'capture') {
            window.addEventListener('keydown', handleKeyDown, true);
            return () => window.removeEventListener('keydown', handleKeyDown, true);
        }
    }, [mode, handleKeyDown]);

    // Focus text input when entering text mode
    useEffect(() => {
        if (mode === 'text' && textRef.current) {
            textRef.current.focus();
            textRef.current.select();
        }
    }, [mode]);

    const displayed = format(current);

    // ── text input mode ───────────────────────────────────
    if (mode === 'text') {
        return (
            <div className="vtt-hotkey-text-row">
                <input
                    ref={textRef}
                    id="vtt-hotkey-text-input"
                    className="vtt-hotkey-text-input"
                    placeholder="e.g. ctrl+space"
                    value={textVal}
                    onChange={e => setTextVal(e.target.value)}
                    onKeyDown={e => {
                        if (e.key === 'Enter') {
                            const v = textVal.trim().toLowerCase();
                            if (v) applyCombo(v);
                        }
                        if (e.key === 'Escape') { setMode('idle'); }
                    }}
                    aria-label="Type hotkey combination"
                />
                <button
                    className="vtt-hotkey-text-ok"
                    onClick={() => { const v = textVal.trim().toLowerCase(); if (v) applyCombo(v); }}
                    title="Apply"
                >✓</button>
                <button
                    className="vtt-hotkey-text-cancel"
                    onClick={() => setMode('idle')}
                    title="Cancel"
                >✕</button>
            </div>
        );
    }

    // ── idle / capture mode ───────────────────────────────
    return (
        <div className="vtt-hotkey-wrap">
            <button
                id="vtt-hotkey-capture"
                className={[
                    'vtt-hotkey-badge',
                    mode === 'capture' ? 'vtt-hotkey-badge--capturing' : '',
                    errorMsg ? 'vtt-hotkey-badge--error' : '',
                ].join(' ').trim()}
                onClick={() => { setMode(m => m === 'capture' ? 'idle' : 'capture'); setErrorMsg(null); }}
                title={mode === 'capture' ? 'Press new shortcut… (Esc to cancel)' : 'Click to change hotkey'}
                aria-label={`Hotkey: ${displayed}. ${mode === 'capture' ? 'Press new shortcut' : 'Click to change'}`}
            >
                {mode === 'capture'
                    ? <span className="vtt-hotkey-badge__hint">press keys…</span>
                    : displayed}
            </button>
            {mode === 'capture' && (
                <button
                    className="vtt-hotkey-type-link"
                    onClick={() => { setMode('text'); setTextVal(current || ''); }}
                    title="macOS intercepts some keys (e.g. ⌃Space). Type the combo instead."
                >type it</button>
            )}
            {errorMsg && (
                <div className="vtt-hotkey-error-tip" role="alert">
                    {errorMsg}
                </div>
            )}
        </div>
    );
}



function App() {
    const [appState, setAppState] = useState(APP_STATES.IDLE);
    const [statusText, setStatusText] = useState('Ready to dictate');
    const [launchAtLogin, setLaunchAtLogin] = useState(false);
    const [hotkeyConflict, setHotkeyConflict] = useState(false);
    const [micDenied, setMicDenied] = useState(false);
    const [elapsedSecs, setElapsedSecs] = useState(0);
    const [transcriptionText, setTranscriptionText] = useState('');
    const [showClipboardToast, setShowClipboardToast] = useState(false);
    const [config, setConfig] = useState({ model: 'base', language: 'en', hotkey: 'ctrl+space' });

    // Load initial values from Go backend
    useEffect(() => {
        GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        GetLaunchAtLogin().then(setLaunchAtLogin).catch(() => setLaunchAtLogin(false));
        GetConfig().then(setConfig).catch(() => setConfig({ model: 'base', language: 'en' }));
    }, []);

    function handleModelChange(model) {
        SetModel(model)
            .then(() => setConfig((c) => ({ ...c, model })))
            .catch((err) => console.error('SetModel failed:', err));
    }

    function handleLanguageChange(language) {
        SetLanguage(language)
            .then(() => setConfig((c) => ({ ...c, language })))
            .catch((err) => console.error('SetLanguage failed:', err));
    }

    function handleHotkeyChange(combo) {
        return SetHotkey(combo)
            .then(() => {
                setConfig((c) => ({ ...c, hotkey: combo }));
                setHotkeyConflict(false); // clear the conflict banner on success
            })
            // Reject so HotkeyCapture can show error flash
            .catch((err) => { console.error('SetHotkey failed:', err); return Promise.reject(err); });
    }

    // Listen for hotkey + audio events from Go backend
    useEffect(() => {
        const unsubTrigger = EventsOn('hotkey:triggered', () => {
            setMicDenied(false); // clear any previous permission error on successful start
            setAppState((prev) => {
                if (prev === APP_STATES.IDLE) return APP_STATES.RECORDING;
                if (prev === APP_STATES.RECORDING) return APP_STATES.PROCESSING;
                return APP_STATES.IDLE;
            });
        });

        const unsubConflict = EventsOn('hotkey:conflict', () => {
            setHotkeyConflict(true);
        });

        const unsubMicDenied = EventsOn('audio:permission-denied', () => {
            setMicDenied(true);
            setAppState(APP_STATES.IDLE);
        });

        const unsubTranscription = EventsOn('transcription:result', (text) => {
            setTranscriptionText(text);
            setAppState(APP_STATES.PROCESSING);
        });

        const unsubFallback = EventsOn('paste:fallback', () => {
            setShowClipboardToast(true);
            setTimeout(() => setShowClipboardToast(false), 2000);
        });

        return () => {
            unsubTrigger();
            unsubConflict();
            unsubMicDenied();
            unsubTranscription();
            unsubFallback();
        };
    }, []);

    // Derive status label from app state
    useEffect(() => {
        if (appState === APP_STATES.RECORDING) setStatusText('Recording…');
        if (appState === APP_STATES.PROCESSING) {
            setStatusText('Transcribing…');
            // Auto-return to idle after overlay holds for 1.5s
            const t = setTimeout(() => {
                setAppState(APP_STATES.IDLE);
                setTranscriptionText('');
            }, 1600); // slightly after 1.5s progress bar drains
            return () => clearTimeout(t);
        }
        if (appState === APP_STATES.IDLE) {
            GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        }
    }, [appState]);

    // Elapsed timer — ticks while recording, resets on idle
    useEffect(() => {
        if (appState !== APP_STATES.RECORDING) {
            setElapsedSecs(0);
            return;
        }
        const t = setInterval(() => setElapsedSecs((s) => s + 1), 1000);
        return () => clearInterval(t);
    }, [appState]);

    function handleLaunchToggle(e) {
        const checked = e.target.checked;
        setLaunchAtLogin(checked);
        SetLaunchAtLogin(checked).catch((err) => {
            setLaunchAtLogin(!checked);
            console.error('SetLaunchAtLogin failed:', err);
        });
    }

    // ── Window drag hook ──────────────────────────────────────
    // Uses screen-space mouse coords so any movement of the mouse
    // maps directly to window movement, regardless of zoom/DPR.
    const dragRef = useRef(null); // { startMouseX, startMouseY, startWinX, startWinY }

    const onDragStart = useCallback((e) => {
        if (e.button !== 0) return; // left button only
        e.preventDefault();
        const startWinX = window.screenX;
        const startWinY = window.screenY;
        const startMouseX = e.screenX;
        const startMouseY = e.screenY;
        dragRef.current = { startWinX, startWinY, startMouseX, startMouseY };

        const onMove = (ev) => {
            if (!dragRef.current) return;
            const { startWinX, startWinY, startMouseX, startMouseY } = dragRef.current;
            WindowSetPosition(
                startWinX + ev.screenX - startMouseX,
                startWinY + ev.screenY - startMouseY
            );
        };
        const onUp = () => {
            dragRef.current = null;
            window.removeEventListener('mousemove', onMove);
            window.removeEventListener('mouseup', onUp);
        };
        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp);
    }, []);

    return (
        <>
            <div
                id="App"
                className={`vtt-popover vtt-state-${appState}`}
                data-testid="vtt-root"
            >
                {/* Drag handle — top section containing mic + title + status */}
                <div
                    className="vtt-drag-handle"
                    onMouseDown={onDragStart}
                    title="Drag to move"
                >
                    {/* Mic icon */}
                    <div id="vtt-mic-icon" className="vtt-mic-icon" aria-label="Microphone" role="img">
                        🎙
                    </div>

                    {/* App title */}
                    <div id="vtt-title" className="vtt-title">voice-to-text</div>

                    {/* Status text */}
                    <div id="vtt-status" className="vtt-status-text" aria-live="polite" aria-atomic="true">
                        {statusText}
                    </div>
                </div>


                {/* Hotkey badge — or conflict/permission-denied warning */}
                {micDenied ? (
                    <div id="vtt-hotkey-badge" className="vtt-status-badge" style={{ color: 'var(--vtt-accent)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <span>🎙 Microphone access required</span>
                        <button
                            id="vtt-open-settings"
                            onClick={() => OpenSystemSettings().catch(console.error)}
                            style={{
                                background: 'none', border: '1px solid var(--vtt-accent)',
                                color: 'var(--vtt-accent)', borderRadius: '4px',
                                padding: '2px 6px', fontSize: '10px', cursor: 'pointer',
                                fontFamily: 'var(--vtt-font-mono)',
                            }}
                        >
                            Open Settings
                        </button>
                    </div>
                ) : hotkeyConflict ? (
                    <div id="vtt-hotkey-badge" className="vtt-status-badge" style={{ color: 'var(--vtt-accent)' }}>
                        ⚠ Hotkey conflict — try another key
                    </div>
                ) : (
                    <div id="vtt-hotkey-badge" className="vtt-status-badge" title="Press to toggle recording">
                        {(() => {
                            const c = config.hotkey || 'ctrl+space';
                            const mods = { ctrl: '⌃', option: '⌥', shift: '⇧', cmd: '⌘' };
                            const parts = c.toLowerCase().split('+');
                            const key = parts[parts.length - 1];
                            const sym = parts.slice(0, -1).map(m => mods[m] || m).join('');
                            const label = { space: 'Space', tab: 'Tab' }[key] || key.toUpperCase();
                            return `${sym}${label} to record`;
                        })()}
                    </div>
                )}

                {/* Settings section */}
                <div className="vtt-divider" />

                <label className="vtt-toggle">
                    <span className="vtt-toggle__label">Launch at login</span>
                    <span className="vtt-toggle__switch">
                        <input
                            id="vtt-launch-at-login"
                            type="checkbox"
                            checked={launchAtLogin}
                            onChange={handleLaunchToggle}
                            aria-label="Launch at login"
                        />
                        <span className="vtt-toggle__track" />
                    </span>
                </label>

                <SettingsPanel
                    config={config}
                    onModelChange={handleModelChange}
                    onLanguageChange={handleLanguageChange}
                    onHotkeyChange={handleHotkeyChange}
                />

                {/* HUD pill — overlays bottom of card while recording */}
                {appState === APP_STATES.RECORDING && (
                    <RecordingHUD elapsedSecs={elapsedSecs} />
                )}

                {/* Transcription overlay — overlays bottom of card after stop */}
                {appState === APP_STATES.PROCESSING && transcriptionText && (
                    <TranscriptionOverlay text={transcriptionText} />
                )}

                {/* Clipboard fallback toast — shown briefly after paste failure */}
                {showClipboardToast && <ClipboardToast />}
            </div>
        </>
    );
}

export default App;
