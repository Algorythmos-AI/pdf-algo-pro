# Troubleshooting

User-facing troubleshooting will be collected here as questions arrive through support. For now,
known product behaviours:

| Symptom | Explanation |
|---|---|
| AI options say they are unavailable | On-device intelligence needs an Apple Intelligence-capable device with Apple Intelligence turned on and its model downloaded. The app states which condition is missing. |
| A long document asks to use Private Cloud Compute | The on-device model has a limited context; longer requests need the opt-in cloud tier. Nothing is sent without consent. |
| Private Cloud Compute stops working for the day | Apple applies a daily per-user limit; the app falls back to on-device processing. |

Engineering troubleshooting (CI, builds, releases) lives in the
[quality gates](../process/quality-gates.md) and the [runbooks](../process/runbooks/incident-response.md).
