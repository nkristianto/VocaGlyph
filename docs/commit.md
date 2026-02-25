git subtree split --prefix=swift-version -b swift-temp

git push swift-origin swift-temp:main 


```
hdiutil create -volname "VocaGlyph" -srcfolder VocaGlyph.app \
  -ov -format UDZO VocaGlyph.dmg
```


tccutil reset Microphone com.vocaglyph.app



mlx-community/Qwen2.5-7B-Instruct-4bit)
[2026-02-25 03:37:49.820] [INFO ] AppStateManager: Creating LocalLLMEngine for model: mlx-community/Qwen2.5-7B-Instruct-4bit
Publishing changes from background threads is not allowed; make sure to publish values from the main thread (via operators like receive(on:)) on model updates.
Publishing changes from background threads is not allowed; make sure to publish values from the main thread (via operators like receive(on:)) on model updates.
Publishing changes from background threads is not allowed; make sure to publish values from the main thread (via operators like receive(on:)) on model updates.
[2026-02-25 03:37:51.689] [INFO ] LocalLLMEngine: Model unloaded from memory.
[2026-02-25 03:37:57.652] [INFO ] Hotkey Service updated to listen for: ⌃ ⇧ C (Code: 8, Flags: 393216)
[2026-02-25 03:37:57.652] [INFO ] AppStateManager: Switching post-processing engine to: local-llm
[2026-02-25 03:37:57.652] [INFO ] AppStateManager: Switching post-processing engine to LocalLLMEngine (model: mlx-community/Qwen3-0.6B-4bit)
[2026-02-25 03:37:57.652] [INFO ] AppStateManager: Creating LocalLLMEngine for model: mlx-community/Qwen3-0.6B-4bit
Publishing changes from background threads is not allowed; make sure to publish values from the main thread (via operators like receive(on:)) on model updates.
Updating ObservedObject<WhisperService> from background threads will cause undefined behavior; make sure to update it from the main thread.
Updating ObservedObject<AppStateManager> from background threads will cause undefined behavior; make sure to update it from the main thread.
Updating ObservedObject<SettingsViewModel> from background threads will cause undefined behavior; make sure to update it from the main thread.