# Phase 2b — Honest Piano Roll Edit Suite

**Branch:** `phase-2b-edit-suite`  
**Base:** `main` (latest with Phase 2 vertical slice merged)  
**Date:** 2026-09-08

## Executive Summary

Phase 2b delivers a **focused editing suite** for the piano roll, enabling users to tap-to-select notes and perform standard editing operations: nudge (drag to adjust timing/pitch), delete, lock, split, and merge. All operations respect locked notes, and the fixture picker continues to work smoothly with session-local edits.

## What Shipped

### 1. ✅ Tap-to-Select Notes
- **File:** `ios/OpenBard/OpenBard/PianoRollView.swift`
- Implemented hit testing to select notes by tapping on the piano roll
- Selected notes show in orange; locked notes show in green
- Selection clears when switching fixtures or edit modes
- Uses `DragGesture` with minimum distance to distinguish taps from drags

### 2. ✅ Nudge with Drag Gesture
- **File:** `ios/OpenBard/OpenBard/ContentView.swift`
- Nudge mode now fully wired: toggle button activates drag gesture
- Horizontal drag adjusts onset time (10ms per pixel)
- Vertical drag adjusts pitch (20 pixels per semitone)
- Locked notes resist nudging (operation silently rejected)
- Onset clamped to 0 (no negative times), pitch clamped to MIDI 0-127

### 3. ✅ Delete and Lock Fully Wired
- **Files:** `ios/OpenBard/OpenBard/ContentView.swift`
- Delete removes selected note from transcription
- Lock marks note as confirmed (green visual, resists edits)
- Buttons disabled when no note selected
- Selection cleared after operation

### 4. ✅ Split and Merge Operations
- **Files:** `ios/OpenBard/OpenBard/ContentView.swift`, `ios/OpenBard/OpenBard/NoteHelpers.swift`
- **Split:** Divides note at midpoint into two equal-duration notes
  - Minimum duration: 0.1 seconds (rejects shorter notes)
  - Locked notes cannot be split
  - Selection moves to second (newly created) note after split
- **Merge:** Finds adjacent same-pitch note and combines
  - Adjacency tolerance: 50ms gap between notes
  - Takes max velocity and confidence from both notes
  - Locked notes cannot be merged
  - Selection moves to merged note
- Buttons disabled for locked notes or when no note selected

### 5. ✅ Fixture Picker Preserved
- **File:** `ios/OpenBard/OpenBard/ContentView.swift`
- Switching fixtures resets edit mode and clears selection
- Edits are session-local (in-memory only)
- Fixture JSON files remain unchanged
- No crashes on fixture switch

### 6. ✅ Light Unit Tests
- **File:** `ios/OpenBard/OpenBardTests/OpenBardTests.swift`
- `NoteHelpers` module with pure functions for split/merge/nudge logic
- 11 new tests covering:
  - Split at midpoint, reject short notes, reject locked notes
  - Merge adjacent notes, reject different pitches, reject locked notes
  - Nudge timing and pitch, reject invalid pitch, clamp negative time
  - Find merge candidate
- All tests use Swift Testing framework (`@Test` macro)

### 7. ✅ Documentation Updated
- **File:** `PHASE2B_REPORT.md` (this file)
- Clear behavior documented for each operation
- Out-of-scope items listed (live Basic Pitch, Core ML, ScoreBuilder)

## File Changes

```
ios/OpenBard/OpenBard/ContentView.swift           (modified, +117 lines)
ios/OpenBard/OpenBard/PianoRollView.swift         (modified, +31 lines)
ios/OpenBard/OpenBard/TranscriptionModels.swift   (modified, +10 lines)
ios/OpenBard/OpenBard/NoteHelpers.swift           (new file, 85 lines)
ios/OpenBard/OpenBardTests/OpenBardTests.swift    (modified, +164 lines)
```

## Behavior Documentation

### Tap-to-Select
- Tap anywhere on a note rectangle to select it
- Selected note shows in **orange**
- Locked notes show in **green** (whether selected or not)
- Tap on empty space deselects (returns to no selection)

### Nudge
1. Tap **"Nudge"** button to enter nudge mode (button shows checkmark)
2. Tap a note to select it
3. Drag the note horizontally (timing) or vertically (pitch)
4. Release to apply the change
5. Tap "Nudge ✓" again to exit nudge mode

**Constraints:**
- Locked notes cannot be nudged
- Onset clamped to ≥ 0
- Pitch clamped to MIDI 0-127

### Delete
- Select a note, tap **"Delete"**
- Note removed from transcription
- Selection cleared

### Lock
- Select a note, tap **"Lock"**
- Note marked as confirmed (turns green)
- Locked notes resist split/merge/nudge/delete

### Split
- Select a note (≥ 0.1s duration), tap **"Split"**
- Note divided at midpoint into two equal-duration notes
- Selection moves to second note
- Locked notes cannot be split (button disabled)

### Merge
- Select a note, tap **"Merge"**
- Finds adjacent same-pitch note within 50ms
- If found, combines into single note spanning both
- Takes max velocity and confidence
- Selection moves to merged note
- If no candidate, operation does nothing
- Locked notes cannot be merged (button disabled)

## Out of Scope (Deferred to Future Phases)

- **Live TensorFlow Basic Pitch in worker** (known Python dependency conflicts)
- **On-device Core ML conversion** (requires macOS/Xcode tooling)
- **ScoreBuilder / MusicXML export** (Phase 3)
- **Guided recording UI** (Phase 3+)
- **Persistent save of edits** (future: export edited transcription to JSON)
- **Multi-select** (optional enhancement; single-select shipped)
- **Undo/redo** (future enhancement)

## Testing in Simulator

1. **Prerequisites:** Xcode 15+, macOS with iOS 17+ simulator runtime

2. **Build and run:**
   ```bash
   cd ios/OpenBard
   open OpenBard.xcodeproj
   # Select iPhone 15 simulator or similar
   # Build and run (⌘R)
   ```

3. **Try editing:**
   - Tap **"Isolated Piano"** fixture (21 Basic Pitch notes)
   - Tap a note to select it (turns orange)
   - Tap **"Lock"** to confirm the note (turns green)
   - Select an unlocked note, tap **"Delete"** to remove it
   - Tap **"Nudge"**, select a note, drag it left/right (time) or up/down (pitch)
   - Select a long note (e.g., 1 second), tap **"Split"** to divide it
   - Select a split note, tap **"Merge"** to recombine with its sibling
   - Switch fixtures to reset (edits are session-local)

4. **Play fixture audio:**
   - Tap **"Play"** to hear the isolated piano recording (10 seconds)
   - Observe how edited notes align (or don't) with the audio

## Known Limitations

1. **No undo/redo:** Edits are destructive in-session (can reset by switching fixtures)
2. **No persistent save:** Edits lost when app restarts or fixture switches
3. **Merge requires adjacency:** Only finds notes within 50ms; won't merge distant notes
4. **Single-select only:** Multi-select not implemented (was optional in requirements)
5. **No visual feedback during drag:** Note position updates only after release (future: live preview)

## CI Verification

The full `./scripts/verify` will:
- Run worker pytest (7 tests, including fixture eval)
- Build iOS app with xcodebuild (syntax check, no runtime tests yet)

**Local syntax check (if xcodebuild available):**
```bash
cd /workspace
./scripts/verify
```

## Next Steps (for maintainer)

1. **Merge to main** when ready (user will merge manually, no PR opened)
2. **Phase 3 focus:**
   - ScoreBuilder with quantization
   - MusicXML / MIDI export
   - Guided recording UI
3. **Future enhancements:**
   - Persistent save (export edited transcription JSON)
   - Undo/redo stack
   - Multi-select for batch operations
   - Live preview during nudge drag
   - On-device Core ML Basic Pitch

---

**Delivered:** 2026-09-08  
**Status:** Ready for merge  
**Branch:** `phase-2b-edit-suite` (push only, no PR per user request)
