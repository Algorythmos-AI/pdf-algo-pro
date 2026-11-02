# summarize.chunk

## [1.1.0] - Unreleased

### Changed

- "Write 3 to 6 short sentences" became "Write up to 6 short sentences; write fewer for a short document".

### Why

- `Assumption:` a sentence floor makes the model pad a sparse document such as a business card, and
  grounding then drops the padding. This cause is reasoned, not observed. Validation plan: the
  dropped-sentence table in `ai-evaluation-live.md` from a device run.

### Evaluation

- Recorded-response suite only. The on-device run is pending, so this version has not passed the
  evaluation gate yet.
