---
name: session-log
description: End-of-session documentation routine for RougeXHunter - write the session note into the Obsidian vault (GameNotes/), update the daily note and every system note whose subject changed, lint wikilinks, then commit and push the vault to GitHub. Use when a working session is wrapping up (before the final message), or when the user says "log this session" / "document what we did".
---

# /session-log

Documents the session that is ending into `GameNotes/` (the Obsidian vault, its
own git repo) and publishes it to
https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault. Rule from
`CLAUDE.md` §6: **every session, no exceptions** - a session that changed
nothing still gets a five-line note.

## Trigger
- The work of a session is done and the final message is about to be written.
- The user asks to log / document the session.

## In a cloud session
Run `bash scripts/cloud_bootstrap.sh --graph` first. If it reports the vault as missing, do not run this routine
or `vault_session.js`: tell the owner, write the session note to `pending-vault-notes/<date>-<topic>.md`, and send
it with `bash scripts/push_docs_to_main.sh "message"`. The next session that has the vault moves those notes in,
then clears them with `--clear-pending`.

## Steps (in this order)
1. **Open the note**
   ```
   node scripts/vault_session.js new --title "<5-8 word title>" --summary "<one sentence>"
   ```
   Prints the path of `GameNotes/Sessions/<UTC date>-<slug>.md`, logs an
   `opened` line into `GameNotes/Daily/<date>.md`, rebuilds `Sessions/_Index.md`
   and the "Recent sessions" block on `00-Home.md`.
2. **Fill the note** - facts only, cite files as `path/File.luau:LINE`:
   - Goal (what was asked, in the user's words where possible)
   - What changed (table: area, files, change) - include new files, deleted files, config edits
   - Decisions (and the reason for each; link the note that holds the detail)
   - Verification (commands run and their result; say plainly what was NOT verified)
   - Open threads / next (what is unfinished, blocked, or proposed)
   - Feedback for the owner (the most useful honest observations from this session)
3. **Daily summary** - 2-5 bullets under `## Summary` in `GameNotes/Daily/<date>.md`.
   Never edit between the `<!-- AGENTIC-OS:RECENT-CHANGES:START/END -->` markers.
4. **Keep `HANDOFF.md` true** - if the owner's rules, decisions, open questions, known bugs or next
   steps changed, update it in the game repo and send it with `bash scripts/push_docs_to_main.sh "message"`.
   **Keep system notes true** - for every service, module, tool or web-hub area
   whose behaviour or plan changed, update its note under `GameNotes/Systems/`,
   `GameNotes/Reference/` or `GameNotes/Web-Hub/` in the same turn (the Golden
   Rule, applied to docs). New long-lived subject -> new note with frontmatter
   (`title`, `tags`, `date`, `status`, `parent`, `related`, `source_files`) and a
   link from `00-Home.md`. Tick anything finished in `Roadmap.md`.
5. **Feedback** - add honest critique to `GameNotes/Feedback/Project-Feedback.md`, move anything
   solved to its Resolved list, and give the highlights in the final message. The owner asked for
   constant feedback, so do not soften it.
6. **Graph and lint**
   ```
   npm run vault:graph
   npm run vault:lint
   ```
   Fix every problem before publishing.
7. **Publish** - use the commit attribution line the current session specifies.
   ```
   npm run vault:publish -- --message "Session <date>: <title>" --trailer "<attribution line>"
   ```
   Report the commit URL it prints in the final message.

## Input / Output paths
- In: the session's own history; `GameNotes/Templates/Session-Note-Template.md`.
- Out: `GameNotes/Sessions/<date>-<slug>.md`, `GameNotes/Daily/<date>.md`,
  `GameNotes/Sessions/_Index.md`, `GameNotes/00-Home.md` (recent block), any
  updated notes, one commit on the vault's `main` pushed to GitHub.

## NEVER DO
- NEVER skip publishing because "nothing big happened".
- NEVER write `.env` values, API keys, tokens or personal data into the vault.
- NEVER edit `Sessions/_Index.md` or marker blocks by hand - they are generated.
- NEVER force-push, amend, or rewrite history in the vault repo.
- NEVER commit other game repo files as part of this routine. Only `HANDOFF.md` and pending notes go, through the script.
- NEVER describe work as verified when it was not; write "not verified" instead.
