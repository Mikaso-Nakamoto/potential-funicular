# Workflow Skills

How to work with coding agents on a real project, day after day. These skills are the house rules the user repeats in every thread, turned into procedures with scripts:
- show me the screenshots;
- score it and get it to 8;
- ship every change properly;
- keep the other threads in line.

They're portable. Project specifics (hosting, changelog format, capture folders) go in the project's `AGENTS.md`, or in an optional local `references/<project>.md` next to a skill.

## Choose the right skill

| Need | Start with |
| --- | --- |
| Show real screenshots of the start, key moment and result as work progresses, unasked | [`workflow-progress-screenshots`](workflow-progress-screenshots/SKILL.md) |
| Score work out of 10 on an anchored rubric and improve it round by round to a target | [`workflow-score-to-target`](workflow-score-to-target/SKILL.md) |
| Ship a change: screenshots, changelog, tests, commit, fast-forward push, draft-then-live publish, measured sizes, a 50 MB stop | [`workflow-ship-change`](workflow-ship-change/SKILL.md) |
| Oversee many agent threads on one repo: what merged, what's live, what to archive, what got cut off | [`workflow-threads-manager`](workflow-threads-manager/SKILL.md) |
| Co-author a real document: gather context, iterate the structure, test it on readers | [`doc-coauthoring`](doc-coauthoring/SKILL.md) |
| Write internal comms in company formats: 3P updates, newsletters, status reports, incident reports | [`internal-comms`](internal-comms/SKILL.md) |
| Create or improve a skill itself, and measure how well it performs | [`skill-creator`](skill-creator/SKILL.md) |

## How they fit together

1. Build with **progress screenshots** from the first working version onward.
2. When the user names a bar, **score to target**, with a picture per round.
3. **Ship the change** once it meets the bar.
4. **The threads manager** checks that every thread shipped this way: on `main`, in the changelog with pictures, live, and archived when done.

## Scripts at a glance

- `workflow-progress-screenshots/scripts/capture.mjs`: a headless Chrome screenshot over CDP, with no dependencies. Supports phone viewports, ready-waits, JS steps, and page-error output.
- `workflow-progress-screenshots/scripts/compare.py`: labelled side-by-side panels (before/after, or start/moment/result).
- `workflow-ship-change/scripts/commit-size.sh`, `push-main.sh`, `upload-size.sh`, `verify-live.sh`: measured sizes, a fast-forward-only push with a 50 MB stop, and live checks that catch "page 200, art 404".
- `workflow-threads-manager/scripts/repo-status.sh`, `audit-changelog.py`, `live-check.sh`, `save-captures.sh`, `contact-sheet.py`: branch and worktree status, a changelog-coverage audit, live health, safe archiving, and picture sheets.

## Document and communication skills (Anthropic, Apache-2.0)

Three skills from [anthropics/skills](https://github.com/anthropics/skills) that share this category's premise — a repeatable procedure with checks, not a one-off prompt:

- [`doc-coauthoring`](doc-coauthoring/SKILL.md) — a three-stage workflow for real documents (specs, proposals, decision docs, RFCs): context gathering, refinement of structure, then reader testing. Fits the same loop as `workflow-score-to-target`, applied to prose instead of UI.
- [`internal-comms`](internal-comms/SKILL.md) — company formats for 3P updates, newsletters, FAQ responses, status reports, leadership updates, incident reports. Templates live next to the skill.
- [`skill-creator`](skill-creator/SKILL.md) — how to write a new skill, improve an existing one, and measure its performance. Directly relevant to this repository: it encodes the `SKILL.md` contract the rest of the library follows.

Each folder carries its own `LICENSE.txt` (Apache-2.0).
