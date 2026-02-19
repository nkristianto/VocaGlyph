import { useState, useEffect } from 'react';
import './App.css';
import { GetStatus, GetLaunchAtLogin, SetLaunchAtLogin, OpenSystemSettings } from '../wailsjs/go/main/App';
import { EventsOn } from '../wailsjs/runtime/runtime';

// App state drives .vtt-state-* class on root — controls all visual states
const APP_STATES = {
    IDLE: 'idle',
    RECORDING: 'recording',
    PROCESSING: 'processing',
};

const HOTKEY_LABEL = '⌃Space';

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

function App() {
    const [appState, setAppState] = useState(APP_STATES.IDLE);
    const [statusText, setStatusText] = useState('Ready to dictate');
    const [launchAtLogin, setLaunchAtLogin] = useState(false);
    const [hotkeyConflict, setHotkeyConflict] = useState(false);
    const [micDenied, setMicDenied] = useState(false);
    const [elapsedSecs, setElapsedSecs] = useState(0);
    const [transcriptionText, setTranscriptionText] = useState('');

    // Load initial values from Go backend
    useEffect(() => {
        GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        GetLaunchAtLogin().then(setLaunchAtLogin).catch(() => setLaunchAtLogin(false));
    }, []);

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

        return () => {
            unsubTrigger();
            unsubConflict();
            unsubMicDenied();
            unsubTranscription();
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

    return (
        <>
            <div
                id="App"
                className={`vtt-popover vtt-state-${appState}`}
                data-testid="vtt-root"
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
                        ⚠ ⌃Space conflict — choose another key
                    </div>
                ) : (
                    <div id="vtt-hotkey-badge" className="vtt-status-badge" title="Press to toggle recording">
                        {HOTKEY_LABEL} to record
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
            </div>

            {/* HUD pill — visible during recording only */}
            {appState === APP_STATES.RECORDING && (
                <RecordingHUD elapsedSecs={elapsedSecs} />
            )}

            {/* Transcription overlay — visible after recording stops with result */}
            {appState === APP_STATES.PROCESSING && transcriptionText && (
                <TranscriptionOverlay text={transcriptionText} />
            )}
        </>
    );
}

export default App;
