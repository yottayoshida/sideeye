---
name: sideeye-report
description: Draft an issue for another project's maintainers from a Sideeye FAIL on their tool — first reading the project's contribution rules and its policy on AI- or LLM-written text, and stopping if a drafted report would break them. Produces a draft for the person you work for to approve word for word; never files it. Use when asked to report a Sideeye finding upstream.
---

# Draft an upstream report from a Sideeye FAIL

The person you work for files the report, in their own name, after reading every word. You
draft it — or, where the project forbids that, you stop and say why.

## 0. Read the project's rules before anything else

Read `CONTRIBUTING`, the issue templates, the code of conduct, and any policy on AI- or
LLM-generated contributions (often in `CONTRIBUTING`, an `AGENTS.md`, or the project's
governance pages).

**Produce only what the policy permits; everything else is the person's.**

- **If it forbids LLM-written or tool-generated reports, stop.** Tell the person the report
  is theirs to write in their own words, or not to file. Translate their text only if the
  policy itself allows a machine translation, marked as it asks, with the original beside it
  — translate, never compose. A disclosure paragraph of yours is not the marking such a
  policy asks for. For the measured facts, point them to `sideeye evidence <case.json>`; do
  not arrange those facts into a report for them.
- **If it allows them on conditions** (a statement, a label, a template, a length, AI for code
  but not for issues), meet each condition, and note where the policy lives so the person
  can check.
- If there is no policy, say that you looked and where.

## 1. Decide whether there is a report at all

- **Whether a finding goes upstream was decided before measuring**, by the person you work
  for. If they did not decide to report on this project, stop and ask; a fresh FAIL in hand
  is not the moment to decide.
- **Is it new?** Search the project's tracker, open and closed, for each distinctive word on
  its own — the file, the operation, the symptom — as well as for phrases, and the person's
  own earlier reports. If a near neighbour exists, the report must say how this differs, or
  not be written.
- **Read the current upstream source**, not only the packaged build that was measured,
  and say in the report that you did. A finding upstream has already fixed is not a report.

## 2. Let the recovery choose the opening

Write down how a user recovers first.

| Recovery | Opening paragraph | Fourth section |
|---|---|---|
| one command (`mv file~ file`) | **Up front: this is minor, and closing it as won't-fix is a perfectly good outcome.** | why it might still be worth a line of documentation |
| a person must work out what to delete, and the tool complains until they do | **No data is lost by this.** — then what does break and that it stays broken | what would close it |
| none — the bytes are gone | no mitigating opening at all | why this one may be worth more than the usual in-place-write report |

Calling unrecoverable loss minor is false, not polite.

## 3. Write the sections, in this order

1. **The opening paragraph** from the table, before any heading.
2. **`## What happens`** — the mechanism, the tool's own source quoted with the file named;
   what its design already handles, and what a killed process escapes.
3. **`## Measured`** — literals, not characterisations: version, package, platform; the
   write sequence as it was traced; which crash point of how many; the state before and
   after with byte counts; the recovery actually run (or that the bytes are nowhere); how
   many explored worlds showed it. `sideeye evidence <case.json>` prints most of this.
4. **`## Why this is different from #N`** — only when the tracker holds a near neighbour.
5. **The fourth section** from the table. Name at most two responses, cheaper first, say
   you have no stake in which, and say the dearer one may not be worth it.
6. **`## Disclosure`** — the tool named and linked; one or two sentences on what it does;
   the person's own relationship to it, as it is (ask; do not assume none); and *if you
   would rather not have tool-generated reports on this tracker, say so and I will stop*.
   Then the invariant in one sentence, and — only if the run declared a checker — that the
   checker was shown to fail on deliberately corrupted state before the run.
7. **`## Not claimed`** — power loss, torn writes, concurrent processes: a process kill says
   nothing about what the filesystem does with half-flushed data. Then what of this
   tool was not measured.

Leave out: a tested patch or an offer to send a pull request (that comes only after a
maintainer engages); an opening that is not a fact (no thanks, no aside); your plans.

## 4. Hand the draft over

Give the person the whole text exactly as it would be posted, in the project's language,
with nothing of yours mixed into it — commentary goes before or after, clearly apart. They
read it, change it and file it. Do not file it, and do not open the issue for them.

Reference: [the full shape, with the reports it was drawn from](https://github.com/yottayoshida/sideeye/blob/main/spike/upstream-report-template.md),
[the evidence bundle](https://github.com/yottayoshida/sideeye/blob/main/docs/evidence.md).
