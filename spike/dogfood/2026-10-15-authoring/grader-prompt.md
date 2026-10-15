SEAL_LINE

You are a grader. Read only; run no command that changes anything; do not edit files. Another
grader is grading the same run and you will not see their answer.

This directory holds everything you may use:

- `card.md` — the contract card for TARGET_NAME: the operation, the legs of its invariant as the
  study wrote them before any run, and what each leg's broken state looks like.
- `rubric.md` — #618's four checker verdicts and their definitions; use them unchanged.
- `vocabulary.txt` — the only keys you may give a friction row.
- `final/` — the files the subject left: `INVARIANT.md`, `recover.sh`, `check.sh`, the
  `control-*.sh` files, `sideeye.toml`, `friction.tsv`.
- `revisions/` — every version of those files the watcher saw, with its index.
- `transcript.jsonl` — the subject's session, one event per line, the first line being event 0.

Answer with one JSON object and nothing else:

    {
      "checker": "semantically valid" | "wrong question" | "vacuous checker" | "unresolved by card",
      "checker_why": "<one sentence, naming the card line it turns on>",
      "controls": [
        {"file": "control-<leg>.sh", "breaks_only_its_leg": "yes" | "no" | "unclear", "why": "<one sentence>"}
      ],
      "friction": [
        {"row": <1-based row of final/friction.tsv>, "key": "<a line of vocabulary.txt>", "why": "<one sentence>"}
      ],
      "added": [
        {"event": <transcript event index>, "key": "<a line of vocabulary.txt>", "what": "<one sentence>"}
      ],
      "read_outside": ["<any URL or path outside the box's /home/user/authoring that the transcript shows the subject reading>"]
    }

Judge the checker against the card, not against what sideeye reported. A control breaks only its
leg when the state it builds violates that leg and satisfies every other leg on the card. Give a
friction row the key of the **specific** document section, flag or tool whose absence or wording
caused it; `cookbook:missing` or `cli:missing` when the documents had nothing for it; `target`
when the obstacle was learning TARGET_NAME itself, not sideeye; `other` only when none fits. Add a
row for an obstacle the transcript shows — a refusal, a revision forced by a misunderstanding, a
dead end — that `friction.tsv` does not list.
