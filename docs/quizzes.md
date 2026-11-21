# Quizzes: how to write one

A quiz is a **bank** of questions for one lesson, in `quizzes/<lesson-id>.toml` at the content root (next to `labs/`). The file name must be the lesson id. Each attempt draws only `draw` questions from the bank (default 10), so a retake is different. Questions the learner missed last time come back first (up to half of the next attempt); the rest are random, and the order and the choices are shuffled.

Quizzes are optional and are not a gate. They test recall and reading; whether the learner can actually do the thing is tested by the labs.

## File format

```toml
schema_version = 1
lesson = "networking.subnetting"
draw = 12                      # optional; questions per attempt (1 to the bank size)

[[question]]
id = "mask-26"                 # unique in the file; lowercase letters, digits and '-'. Never reuse or rename:
                               # progress records missed questions by this id.
type = "short"                 # choice | multi | short
prompt = "Write the dotted-decimal subnet mask for a /26 prefix."
answers = ["255.255.255.192"]
explanation = "Two extra bits in the last octet make 128 + 64 = 192."    # required
review = "An address and a mask"                                          # optional
certifications = ["comptia-network-plus/networking-concepts"]             # optional
```

| `type` | Extra fields | Right answer |
|---|---|---|
| `choice` | `choices` (2 to 8) | `answers` holds exactly one of the choice texts, spelled the same |
| `multi` | `choices` (2 to 8) | `answers` holds two or more choice texts; the learner must pick exactly that set; at least one choice is wrong |
| `short` | none | the typed text equals any entry of `answers` after lower-casing and collapsing blanks |

Choices are graded by their **text**, never their position, because the window shuffles them.

## Rules a good question follows

- Every question has an **explanation**. It is shown after the answer, right or wrong.
- `review` names a heading or phrase that really appears in the lesson. `winlab check` fails if it does not.
- A `short` question says what form the answer takes ("number only", "for example /24"), and lists every reasonable spelling in `answers`.
- Test one idea. Prefer questions that need understanding over ones that need recall of a word.
- If a question has a computed answer, **compute it with a tool** (the subnetting bank was checked this way) and do not rely on memory.
- Answers come from the lesson and the cited official documents. A question must not depend on something the lesson never says.
- **Scaffolding fades with level** (`docs/content-plan.md`): early quizzes can be recall; advanced ones should send the learner to the documentation (open-book) rather than ask them to remember syntax.

## Checking

`winlab check course` parses every quiz and reports the question number and key for any problem, plus: file name matches the lesson, the lesson exists, certification tags exist in `certs/catalog.toml`, and each `review` appears in the lesson.

## Not built yet

Generated questions (fresh numbers each attempt, for subnetting), ordering and matching questions, and a view of weak certification domains across all quizzes. The data format leaves room for them (`type` is an enum).
