# 10 — ChatGPT ↔ Gemini Handoff Protocol

## Communication reality
ChatGPT and the user's Gemini environment do not share a direct live control channel in this workflow. The user relays prompts and reports. The user should not need to make technical decisions or rewrite the reports; copy/paste the prepared task and Gemini's structured output.

## Cycle
1. ChatGPT prepares one scoped task prompt with objective, context, allowed actions, prohibited actions and acceptance criteria.
2. User pastes it into the existing Gemini conversation.
3. Gemini reads `AGENTS.md` and relevant docs, executes only the assigned task.
4. Gemini saves full report and raw evidence in the project.
5. Gemini returns a concise structured summary and exact report path.
6. User pastes Gemini's response here; ChatGPT reviews evidence, identifies gaps and issues the next task.
7. Only ChatGPT-reviewed decisions advance architecture; user approves router-impacting actions.

## Handoff payload required from Gemini
- Task ID and status.
- Summary of work.
- Changed file paths.
- Exact commands and source URLs.
- Commit SHAs and license evidence.
- Raw report paths.
- Acceptance criteria status.
- Risks and unknowns.
- Recommended next step.
- Explicit approval requests.

## Rules
- One major task per handoff.
- No generic “done” without evidence.
- If blocked, stop and explain the blocker.
- Never autonomously move to the next phase.
- User is the relay, not the technical integrator.
