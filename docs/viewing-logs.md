# Viewing Application Logs

When developing or troubleshooting VocaGlyph, you might need to view the application's standard output (`print()` and `devLog()` statements). Because VocaGlyph is a macOS accessory app that often runs without a standard terminal attached, here are the best ways to view its logs.

## Option 1: Run the Executable Directly (Recommended for Development)

Instead of using `open build/Release/VocaGlyph.app` which detaches the process, you can execute the actual binary inside the app bundle directly from your terminal. 

This keeps the process attached to your terminal, and all `print()` and `devLog()` statements will appear right there in your console view.

**Command:**
```bash
# Run this from the Swift-version directory
./build/Release/VocaGlyph.app/Contents/MacOS/VocaGlyph
```

*To stop the application, just press `Ctrl+C` in the terminal.*

---

## Option 2: Use the macOS Console App

If you prefer to keep launching the app via the `open` command or by double-clicking the app bundle in Finder, you can use the built-in macOS Console application to capture its logs:

1. Open the **Console** app (you can find it in `Applications > Utilities`, or via Spotlight).
2. Click "Start" in the top bar to begin streaming logs.
3. In the search bar at the top right, type `VocaGlyph` and press Enter. This filters out the system noise so you only see logs originating from our app.

---

## Option 3: Terminal Log Stream (Unified Logging)

You can use the macOS `log` command to stream the unified logging system right in your terminal for that specific process, even if launched via the `open` command.

**Command:**
```bash
log stream --predicate 'process == "VocaGlyph"' --info --debug
```
