import { useState, useEffect } from 'react';
import './App.css';
import { GetStatus, GetLaunchAtLogin, SetLaunchAtLogin } from '../wailsjs/go/main/App';
import { EventsOn } from '@wailsapp/runtime';

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
    const [hotkeyConflict, setHotkeyConflict] = useState(false);

    // Load initial values from Go backend
    useEffect(() => {
        GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        GetLaunchAtLogin().then(setLaunchAtLogin).catch(() => setLaunchAtLogin(false));
    }, []);

    // Listen for hotkey events from Go backend
    useEffect(() => {
        const unsubTrigger = EventsOn('hotkey:triggered', () => {
            setAppState((prev) => {
                if (prev === APP_STATES.IDLE) return APP_STATES.RECORDING;
                if (prev === APP_STATES.RECORDING) return APP_STATES.PROCESSING;
                return APP_STATES.IDLE;
            });
        });

        const unsubConflict = EventsOn('hotkey:conflict', () => {
            setHotkeyConflict(true);
        });

        return () => {
            unsubTrigger();
            unsubConflict();
        };
    }, []);

    // Derive status label from app state
    useEffect(() => {
        if (appState === APP_STATES.RECORDING) setStatusText('Recording…');
        if (appState === APP_STATES.PROCESSING) {
            setStatusText('Transcribing…');
            // Auto-return to idle after a short delay (Story 3 will replace this)
            const t = setTimeout(() => setAppState(APP_STATES.IDLE), 1500);
            return () => clearTimeout(t);
        }
        if (appState === APP_STATES.IDLE) {
            GetStatus().then(setStatusText).catch(() => setStatusText('Ready to dictate'));
        }
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

            {/* Hotkey badge or conflict warning */}
            {hotkeyConflict ? (
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
    );
}

export default App;
