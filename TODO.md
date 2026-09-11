# openBard TODO

The active plan and acceptance criteria live in the
[README roadmap](README.md#roadmap).

## Next

Phase 1 is complete (see `docs/phase1-engine-decision.md`).  
Phase 2 vertical slice is complete (see `PHASE2_REPORT.md`).  
**Phase 2b** is complete (see `PHASE2B_REPORT.md`).

Basic Pitch selected for MVP.

**Phase 2 focus:** Honest piano roll and tight edit loop.

- [x] Integrate Basic Pitch behind `Transcriber` adapter.
- [x] Process real audio from bundled fixture (not hardcoded notes).
- [x] Extend contract to capture confidence/uncertainty from model.
- [x] Build interactive piano-roll editor with confidence visualization.
- [x] Implement note editing: split, merge, nudge, lock, delete.
- [x] Add fixture-backed evaluation to CI (recall/spurious-note rates).

**Phase 2b accomplishments:**
- [x] Tap-to-select notes on piano roll
- [x] Nudge with drag gesture (adjust timing and pitch)
- [x] Delete and Lock fully wired to selection
- [x] Split notes at midpoint
- [x] Merge adjacent same-pitch notes
- [x] Light unit tests for edit operations
- [x] Documentation updated

See [Phase 2 roadmap](README.md#phase-2--honest-piano-roll-and-tight-edit-loop) 
for full acceptance criteria.

## Future Phases

**Phase 3 (export still open):**
- [x] ScoreBuilder with quantization from locked notes and staff preview
- [ ] MusicXML / MIDI export

**Phase 4:**
- [ ] Guided recording UI

**Future enhancements:**
- [ ] Persistent save (export edited transcription JSON)
- [ ] Undo/redo stack
- [ ] Multi-select for batch operations
- [ ] Live preview during nudge drag
- [ ] On-device Core ML Basic Pitch
