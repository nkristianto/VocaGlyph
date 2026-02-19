import { useState, useEffect } from 'react';
import './App.css';
import { GetStatus, GetLaunchAtLogin, SetLaunchAtLogin } from '../wailsjs/go/main/App';

// App state drives .vtt-state-* class on root — controls all visual states
const APP_STATES = {
    IDLE: 'idle',
    RECORDING: 'recording',
    PROCESSING: 'processing',
};

const HOTKEY_LABEL = '⌃Space';

function App() {
    const [appState, setAppState] = useState(APP_STATES.IDLE);
    const [statusText, setStatusText] = useState('Ready to dictate');
    const [launchAtLogin, setLaunchAtLogin] = useState(false);

    // Load initial values from Go backend
    useEffect(() => {
        GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        GetLaunchAtLogin().then(setLaunchAtLogin).catch(() => setLaunchAtLogin(false));
    }, []);

    // Derive status label from app state
    useEffect(() => {
        if (appState === APP_STATES.RECORDING) setStatusText('Recording…');
        if (appState === APP_STATES.PROCESSING) setStatusText('Transcribing…');
        if (appState === APP_STATES.IDLE) {
            GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        }
    }, [appState]);

    function handleLaunchToggle(e) {
        const checked = e.target.checked;
        setLaunchAtLogin(checked);
        SetLaunchAtLogin(checked).catch((err) => {
            // Revert on failure
            setLaunchAtLogin(!checked);
            console.error('SetLaunchAtLogin failed:', err);
        });
    }

    return (
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

            {/* Hotkey badge */}
            <div id="vtt-hotkey-badge" className="vtt-status-badge" title="Press to start recording">
                {HOTKEY_LABEL} to record
            </div>

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

            {/* Developer state switcher — remove in Story 2 when hotkey wired */}
            {process.env.NODE_ENV === 'development' && (
                <>
                    <div className="vtt-divider" />
                    <div style={{ display: 'flex', gap: '8px' }}>
                        {Object.values(APP_STATES).map((state) => (
                            <button
                                key={state}
                                onClick={() => setAppState(state)}
                                style={{
                                    padding: '4px 10px',
                                    borderRadius: '6px',
                                    fontSize: '11px',
                                    fontFamily: 'var(--vtt-font-mono)',
                                    background: appState === state ? 'var(--vtt-accent-dim)' : 'var(--vtt-bg-surface)',
                                    border: `1px solid ${appState === state ? 'var(--vtt-accent)' : 'var(--vtt-border)'}`,
                                    color: appState === state ? 'var(--vtt-accent)' : 'var(--vtt-text-tertiary)',
                                    cursor: 'pointer',
                                }}
                            >
                                {state}
                            </button>
                        ))}
                    </div>
                </>
            )}
        </div>
    );
}

export default App;
