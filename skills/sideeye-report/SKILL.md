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
governance pages). Read each issue form field by field: every field with
`validations.required: true` must be filled, under the form's own heading, or a bot may close
the report within a minute. A checkbox is a statement — tick "I searched the forum" only after
searching it.

**Produce only what the policy permits; everything else is the person's.**

- **If it forbids LLM-written or tool-generated reports — AI for code but not for issues
  included — stop.** Tell the person the report
  is theirs to write in their own words, or not to file. Translate their text only if the
  policy itself allows a machine translation, marked as it asks, with the original beside it
  — translate, never compose. A disclosure paragraph of yours is not the marking such a
  policy asks for. For the measured facts, point them to `sideeye evidence <case.json>`; do
  not arrange those facts into a report for them.
- **If it allows them on conditions** (a statement, a label, a template, a length), meet each condition, and note where the policy lives so the person
  can check.
- If there is no policy, say that you looked and where.

## 1. Decide whether there is a report at all

- **Whether a finding goes upstream was decided before measuring**, by the person you work
  for. If they did not decide to report on this project, stop and ask; a fresh FAIL in hand
  is not the moment to decide.
- **Is it new?** Search the project's tracker, open and closed, for each distinctive word on
  its own — the file, the operation, the symptom — as well as for phrases, its forum where it
  has one, and the person's own earlier reports. If a near neighbour exists, the report must say how this differs, or
  not be written.
- **Read the current upstream source**, not only the packaged build that was measured, and
  measure the latest release — the development release where the issue form asks for it. A
  finding upstream has already fixed is not a report.

## 2. Keep it to a first screen

Maintainers answer long, sectioned reports as what they look like — "walls of slop", "an
AI-generated novel" — before reading what they found. Aim for a few short paragraphs, about
250 words before any raw output the form requires (version strings, config dumps, logs). The
250 words are an aim, not a limit: never cut what another developer needs to reproduce the
finding to meet it — cut repetition instead. The measurements stay in the run's own record;
the report points at what is needed to see the bug.

Write down how a user recovers first; it picks the opening.

| Recovery | Opening |
|---|---|
| one command (`mv file~ file`) | say it is minor, and that closing it is fine |
| a person must work out what to rename or delete, and the tool stays broken until they do | **No data is lost by this**, then what breaks and that it stays broken |
| none — the bytes are gone | no mitigating opening at all; calling unrecoverable loss minor is false |

## 3. Five things, under the form's headings where there is a form

1. **What a kill leaves**, in one paragraph, opened as the table says.
2. **Where**: one source location, and one sentence on what the design already handles and
   what a killed process does not reach. If the tracker holds a near neighbour, one more
   sentence on how this differs.
3. **How to reproduce**, enough for another developer to run the same experiment: the version;
   the command; the input it started from (the file and its size, the config or flags that
   matter, the filesystem where it matters); the one or two system calls either side of the
   window; how the process was stopped there — the tool and its arguments (the `sideeye replay`
   command line, not its output), not only "between these two calls"; and what was left, beside what an uninterrupted run leaves.
   `sideeye evidence <case.json>` has these.
4. **One way to close it**, and where it is true, that not fixing it is fine.
5. **Disclosure**, in one or two sentences: the tool named and linked, the person's own
   relationship to it as it is (ask; do not assume none), and the AI assistance as the
   project's policy asks it to be said.

Leave out: sections the form did not ask for (no *Measured*, no *Not claimed* — one clause can
carry a limit that matters); the full trace and the evidence table; a tested patch or an offer
to send a pull request (that comes only after a maintainer engages); an opening that is not a
fact; your plans.

## 4. Hand the facts over, then the draft

The person answers for every word, in every report. Where the policy forbids an LLM-written report
or asks for their own text (step 0), they write it. Everywhere else you may draft; give them the facts first — what a kill
leaves, where, how to reproduce, one way to close it — so they can check each against the
run's record, then the draft for them to edit until they understand every sentence and can
defend it. A draft need not be rewritten, but it must be verified: a long draft approved as it
stood is what crystal-lang/crystal#17620 was. Give the whole text back exactly as it would be
posted, in the project's language, with nothing of yours mixed into it — commentary goes
before or after, clearly apart. They read it, change it and file it. Do not file it, and do not
open the issue for them. After filing, watch the first minutes: a bot that closes it names
what was missing.

Reference: [the shape, and why it is short](https://github.com/yottayoshida/sideeye/blob/main/spike/upstream-report-template.md),
[the evidence bundle](https://github.com/yottayoshida/sideeye/blob/main/docs/evidence.md).
