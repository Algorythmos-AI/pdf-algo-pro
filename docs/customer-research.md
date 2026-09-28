# Customer research

The research programme that tests whether the product thesis is true, before and after launch. This
public edition holds the research questions, the jobs-to-be-done hypotheses, the study plan and the
decision rules. **No findings exist yet**: every statement about customers here is a hypothesis
until a study supports or weakens it. Interview guides, survey instruments, recruitment details and
results are in a confidential edition held privately.

Owner: Product · Reviewed: after each study, and at each milestone

## Research questions

1. Which jobs do people on Apple devices hire a PDF app for, and how often? (RQ-1)
2. How do people feel about sending documents to cloud AI, and does it change what they do? (RQ-2)
3. Does private, offline intelligence make people switch, and does it make them pay? (RQ-3)
4. What makes people cancel or abandon PDF apps? (RQ-4)
5. Which onboarding intent do people pick, and does the first task match it? (RQ-5)
6. What packaging feels fair for the value delivered? (RQ-6)

## Jobs-to-be-done hypotheses

| ID | When... | I want to... | So I can... | Moat hypothesis |
|---|---|---|---|---|
| JTBD-1 | a long document arrives (contract, policy, report) | know what it says and what it asks of me | decide quickly without reading every page | SW-1, PAY-2 |
| JTBD-2 | I need a specific fact from a document | find it and trust it | act on it without re-checking the whole file | SW-1, ST-1 |
| JTBD-3 | I receive a form or agreement | fill and sign it on my phone | return it without a computer | parity |
| JTBD-4 | I have paper documents | scan them into searchable PDFs | find them later by their words | ST-1 |
| JTBD-5 | I manage many documents of the same kind | extract the same fields from each | put them in a spreadsheet or my records | PAY-1 |
| JTBD-6 | a document contains sensitive information | work on it without it leaving my control | meet my obligations and feel safe | SW-1, ST-3 |
| JTBD-7 | I am offline | still read, search and ask questions | keep working anywhere | SW-4 |

The SW, PAY and ST hypotheses are defined in the [competitive moat](competitive-moat.md); segments
are in the [target market](target-market.md).

## Study plan

| Study | Phase | Method | Answers |
|---|---|---|---|
| R1 Public review mining | Foundation | Coding recent App Store reviews of leading PDF apps against a fixed frame (billing, sign-in, intrusive AI, privacy, offline, reliability, feature quality) | RQ-2, RQ-4 |
| R2 Problem interviews | Foundation | Semi-structured interviews about past behaviour across the target segments | RQ-1, RQ-2, RQ-4 |
| R3 Message test | Foundation | App Store product page optimisation or landing-page tests of alternative messages | RQ-3 |
| R4 Prototype usability | MVP | Moderated sessions on TestFlight builds with synthetic documents | RQ-5 |
| R5 Willingness to pay | MVP | Survey with price-sensitivity and feature-ranking questions | RQ-6 |
| R6 Beta diary | V1 | Two-week diary during external TestFlight | RQ-1, RQ-3 |
| R7 Churn interviews | After launch | Opt-in interviews with people whose subscription lapsed | RQ-4 |

## Methods and ethics

- Ask about past behaviour, not hypotheticals; never pitch during interviews.
- Participants give informed consent before every session and can withdraw at any time.
- Participants never share real documents; tasks use synthetic documents from the test corpus
  ([testing strategy](testing-strategy.md)).
- Participant identities are never stored in any repository; only pseudonymous IDs are used in
  reports.
- Public reviews are summarised as themes with sample sizes and date ranges; they are never
  reproduced.

## Decision rules

Thresholds for supporting or weakening each hypothesis are fixed before each study starts, so the
goalposts cannot move afterwards. If the privacy hypothesis (SW-1) is weakened, messaging leads with
outcomes and convenience and keeps privacy as a trust signal. If private intelligence does not rank
highly as a reason to pay (PAY-2), intelligence is packaged as part of Pro rather than as a separate
reason to buy. If the onboarding intent does not predict the first task (RQ-5), onboarding is
simplified.

## Status

No studies have run yet. Results are recorded in the confidential edition and summarised here, as
supported or weakened hypotheses, when they are safe to publish.
