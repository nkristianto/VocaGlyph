import {useState, useEffect} from 'react';
import './App.css';
import {GetStatus} from "../wailsjs/go/main/App";

function App() {
    const [status, setStatus] = useState('Loading...');

    useEffect(() => {
        GetStatus().then(setStatus).catch(() => setStatus('Ready to dictate'));
    }, []);

    return (
        <div id="App">
            <div id="microphone-icon" className="mic-icon">🎙</div>
            <div id="app-title" className="app-title">voice-to-text</div>
            <div id="status" className="status-text">{status}</div>
            <div className="hint-text">⌃Space to record</div>
        </div>
    )
}

export default App
