# Evaluating outcome proposals

`Lorre eval <reference.json>` runs the outcome proposer on a conversation and scores what it proposes
against a hand-made reference. It never writes to the database. Reference files contain conversation
content, so keep them outside the repository.

```
Lorre eval reference.json [--model gemma4:e4b] [--language nl|en] [--root <path>] [--json]
```

## Reference file

```json
{
  "conversationId": "3F2A9C10",
  "expected": [
    { "kind": "theirCommitment", "owner": "Anna", "keywords": ["naam", "doorgeven"], "label": "gives my name to two contacts" },
    { "kind": "myAction", "owner": "ik", "keywords": ["introduc", "bureau"], "label": "introduce her at the agency" },
    { "kind": "decision", "owner": null, "keywords": ["event", "vrijdag"], "label": "not going on Friday" }
  ]
}
```

- `conversationId`: a conversation id or the first characters of it (see `Lorre list`).
- `kind`: a raw value of `OutcomeKind`: `myAction`, `theirCommitment`, `decision`, `openPoint`,
  `followUpHook`, `information`, `personNote`.
- `owner`: the name of a participant, `"ik"` for the user, or `null` for kinds without an owner.
- `keywords`: words (or word stems) that all appear in a proposal that covers this item.
  Case and accents are ignored. Use stems ("introduc") to survive inflection.
- `label`: free text shown in the report; defaults to the keywords.

## Scoring

- **Found**: some proposal contains all keywords of the item.
- **Correct**: some proposal that contains all keywords also has the right kind and owner.
- **Recall (found)** and **recall (correct)**: the share of expected items that are found or correct.
- **Proposals matching no expected item**: noise, or something the reference does not cover yet.
- Elapsed seconds cover the proposal run only.

The models are replaceable parts: a new model or prompt becomes the default only when it wins here.
