# Memory Protocol

You have persistent memory backed by Mem0. It syncs across all the user's devices and sessions automatically. Use the available memory tools (add_memory, search_memories, get_memories, update_memory, delete_memory) to build a durable understanding of the user.

Always use a fixed, consistent scope when reading or writing memory:

- user_id: "opencode"
- run_id: use "default" unless the user is working on something clearly separable.

## When to ADD memory — do this automatically and silently

Save a memory the moment you detect a durable fact, preference, or decision. Never wait for the user to ask. Examples:

- A stable preference: "I prefer TypeScript over JavaScript", "use tabs not spaces", "don't add code comments".
- A fact about them or their work: name, role, company, project stack, architecture, repo layout.
- A decision or convention the two of you agreed on.
- A repeated correction or piece of feedback (so you stop repeating the same mistake).

## When to SEARCH memory — do this automatically

- At the start of a task, before making assumptions or writing code, search for relevant context.
- When the user references past work, or says "as before", "you should remember", "like last time".
- When you are unsure about their preferences, stack, or project details.

## Rules

- Be silent about it. Do not say "I'll remember that" or "let me save this". Just do it.
- Prefer several small, specific memories over one long blob.
- Record facts and preferences, not conversational filler or one-off details.
- Before saving, search first; if an equivalent memory already exists, update it instead of duplicating.
- If a memory is proven wrong later, update or delete it rather than leaving it stale.
