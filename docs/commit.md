git subtree split --prefix=swift-version -b swift-temp

git push swift-origin swift-temp:main 


```
hdiutil create -volname "VocaGlyph" -srcfolder VocaGlyph.app \
  -ov -format UDZO VocaGlyph.dmg
```


tccutil reset Microphone com.vocaglyph.app

Here's how to delete it:

Option 1 — From Terminal:

bash
rm "$HOME/Library/Containers/com.vocaglyph.app/Data/Library/Application Support/default.store"
Also delete the -shm and -wal WAL files if they exist alongside it (SQLite write-ahead log files):

bash
rm -f "$HOME/Library/Containers/com.vocaglyph.app/Data/Library/Application Support/default.store-shm"
rm -f "$HOME/Library/Containers/com.vocaglyph.app/Data/Library/Application Support/default.store-wal"
Option 2 — Via Finder:

In Finder, press ⇧⌘G (Go to Folder)
Paste: ~/Library/Containers/com.vocaglyph.app/Data/Library/Application Support/
Delete default.store (and any -shm / -wal files next to it)
