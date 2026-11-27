# Maintaining Port Desk documentation

Purpose: Keep guides, change records and verification instructions useful as the app evolves.

Read this before touching: [Documentation index](INDEX.md), [working instructions](../AGENTS.md), [history](history/INDEX.md), [investigations](investigations/INDEX.md).

Keywords: documentation, ownership, history, investigations, verification, handoff

1. Start at the index. Read the owning guide and trace its source and tests. For a bug, check the system history and active investigations before starting another experiment.
2. Document current behavior in its owning guide in the same task. Include contributor conventions when changing an entry point, configuration, skill pin, accessibility interaction or check. Keep links relative and update incoming links and the index when moving or retiring a guide.
3. Start guides with a title, Purpose, Read this before touching and Keywords. Plans also carry Status. Investigations also carry Status, Last updated and Last reproduced. Keep the three indexes as navigation tables.
4. Record meaningful changes newest first in a system history when evidence warrants an entry. Include date, outcome, symptom or reason, cause, change and rationale, verification limits and references. Register the history in its index and link it from the current guide. Use one owning record for changes spanning systems.
5. Give a substantial cross-task problem one investigation with reproduction, configuration, source identity, facts, hypotheses and experiments. Record expected signals before running experiments. Update results, uncertainty, next experiment and closure criteria at handoff. Keep relevant evidence small and free of credentials or personal data. Keep the index status in step with the record.
6. Check links, named symbols, commands and instructions before handoff. Separate checks actually performed from commands a maintainer can run. Document relevant limits. Check the final changes for authoring conventions that the next developer needs.

For completed file changes, end the handoff with a lowercase `summary:` label above a plain-text code block containing the imperative commit subject, then `description:` above a separate plain-text code block containing one to three sentences on what changed and why. Scope both to the completed work and omit these fields for read-only tasks.
