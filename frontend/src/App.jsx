import { useState, useEffect } from 'react';
import './App.css';
import { GetStatus } from '../wailsjs/go/main/App';

// App state drives .vtt-state-* class on root — controls all visual states
const APP_STATES = {
    IDLE: 'idle',
    RECORDING: 'recording',
    PROCESSING: 'processing',
};

// Hotkey label shown in the badge
const HOTKEY_LABEL = '⌃Space';

function App() {
    const [appState, setAppState] = useState(APP_STATES.IDLE);
    const [statusText, setStatusText] = useState('Ready to dictate');

    // Load initial status from Go backend
    useEffect(() => {
        GetStatus()
            .then(setStatusText)
            .catch(() => setStatusText('Ready to dictate'));
    }, []);

    // Derive status label from app state
    useEffect(() => {
        if (appState === APP_STATES.RECORDING) setStatusText('Recording…');
        if (appState === APP_STATES.PROCESSING) setStatusText('Transcribing…');
        if (appState === APP_STATES.IDLE) {
            GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        }
    }, [appState]);

    return (
        <div
            id="App"
            className={`vtt-popover vtt-state-${appState}`}
            data-testid="vtt-root"
        >
            {/* Mic icon — visual state driven by CSS */}
            <div
                id="vtt-mic-icon"
                className="vtt-mic-icon"
                aria-label="Microphone"
                role="img"
            >
                🎙
            </div>

            {/* App title */}
            <div id="vtt-title" className="vtt-title">
                voice-to-text
            </div>

            {/* Status text — updates with state */}
            <div
                id="vtt-status"
                className="vtt-status-text"
                aria-live="polite"
                aria-atomic="true"
            >
                {statusText}
            </div>

            {/* Hotkey badge */}
            <div
                id="vtt-hotkey-badge"
                className="vtt-status-badge"
                title="Press this hotkey to start recording"
            >
                {HOTKEY_LABEL} to record
            </div>

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
