# openBard TODO

The active plan and acceptance criteria live in the
[README roadmap](README.md#roadmap).

## Next

Phase 1 is complete (see `docs/phase1-engine-decision.md`). Basic Pitch selected 
for MVP.

**Phase 2 focus:** Honest piano roll and tight edit loop.

- [ ] Integrate Basic Pitch behind `Transcriber` adapter.
- [ ] Process real audio from bundled fixture (not hardcoded notes).
- [ ] Extend contract to capture confidence/uncertainty from model.
- [ ] Build interactive piano-roll editor with confidence visualization.
- [ ] Implement note editing: split, merge, nudge, lock.
- [ ] Add fixture-backed evaluation to CI (recall/spurious-note rates).

See [Phase 2 roadmap](README.md#phase-2--honest-piano-roll-and-tight-edit-loop) 
for full acceptance criteria.
