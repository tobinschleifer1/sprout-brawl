# Generated .blend files

These are **build outputs**, regenerated every time a character script runs. Editing one by hand
works for a look or a test, but the next build overwrites it.

The source of truth for every character is its Python script in `../characters/`.

To open one: double-click it, or `File > Open` in Blender. Each contains the finished mesh, the
armature with R15-compatible bone names, the eight palette materials, and a camera already
positioned at the side-on angle the game is played at.

To rebuild them all:

```bash
cd ~/sprout-brawl
for c in thornlock capnspore sunbeam kelpin cacto duststorm mycel frostbud; do
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python blender/characters/$c.py
done
```
