---
session_id: "{{SESSION_ID}}"
created: "{{CREATED_AT}}"
updated: "{{UPDATED_AT}}"
tokens_at_init: {{TOKENS_AT_INIT}}
type: session
ephemeral: true
---

# {{SESSION_TITLE}}

*5-10 word title describing the overall session goal*

---

## Current State

*Most critical section. Describes what is being done RIGHT NOW and the immediate next step.*

**Status:** [in_progress | blocked | completed]  
**Last Activity:** {{LAST_ACTIVITY}}  
**Next Step:** [Describe the immediate next action]

---

## Task Specification

*The original user request, preserved verbatim or paraphrased.*

**Original Request:**
> {{ORIGINAL_REQUEST}}

**Clarifications/Scope:**
- {{CLARIFICATION_1}}
- {{CLARIFICATION_2}}

---

## Files and Functions

*Key files touched, with brief notes on what was done.*

| File Path | Action | Notes |
|-----------|--------|-------|
| `{{FILE_PATH}}` | [created/modified/read] | {{NOTES}} |

**Key Functions/Components:**
- `{{FUNCTION_NAME}}` - {{DESCRIPTION}}
- `{{FUNCTION_NAME}}` - {{DESCRIPTION}}

---

## Errors & Corrections

*Mistakes made and how they were resolved. Prevents repeating errors after compaction.*

### Error Log

| Timestamp | Error | Resolution |
|-----------|-------|------------|
| {{TIME}} | {{ERROR_DESC}} | {{RESOLUTION}} |

### Lessons from Errors
- {{LESSON_1}}
- {{LESSON_2}}

---

## Learnings

*New knowledge gained during this session.*

### Technical Insights
- {{INSIGHT_1}}
- {{INSIGHT_2}}

### Patterns Discovered
- {{PATTERN_1}}
- {{PATTERN_2}}

### References
- [Link or reference to relevant documentation]
- [Link to related memory files]

---

## Session Metadata

**Token Count at Last Update:** {{TOKEN_COUNT}}  
**Tool Calls Made:** {{TOOL_CALL_COUNT}}  
**Duration:** {{DURATION}}  

**Related Memories:**
- `{{MEMORY_FILE_1}}` - {{DESCRIPTION}}
- `{{MEMORY_FILE_2}}` - {{DESCRIPTION}}

---

> **Note:** This is an ephemeral session memory file. It will be deleted when the session ends.
> Critical information should be consolidated into permanent memory files via AutoDream/KAIROS.
