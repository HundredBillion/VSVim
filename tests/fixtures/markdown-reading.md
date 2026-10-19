---
title: Field notes
description: "A small guide to thoughtful software, clear writing, and the pleasure of reading."
---

# Field notes

Good tools make room for the work. A document should feel calm, readable, and easy to navigate, whether it is a short note or a detailed technical guide.

**Start here:** [Reading rhythm](#reading-rhythm) · [Code](#code) · [A second perspective](#perspective) · [Unicode](#caf%C3%A9-notes)

## Reading rhythm

Use **emphasis with intention**, leave *space for an idea to breathe*, and keep `small technical details` close to the sentence they explain. ~~An abandoned approach~~ can remain visible without interrupting the page.

> A good explanation lets the reader spend their attention on the idea.
>
> It has a clear beginning, enough detail, and a natural place to pause.

### A practical checklist

1. Begin with the reader's goal. This intentionally longer sentence wraps onto another line in a narrow pane so the alignment of the text is easy to inspect.
   - Make the next action obvious.
     - Keep related ideas together, even when a nested item has enough text to wrap across several lines in a narrow window.
   - Prefer a concrete example.
2. Check the details.

   This second paragraph belongs to the same list item and keeps its indentation.

   ```python
   def greet(name: str) -> str:
       return f"Hello, {name}!"
   ```

- [x] Preserve the original document.
- [ ] Take time to read it at a comfortable width.

## Code

```rust
// A tiny example with a string, a number, and a comment.
fn main() {
    let place = "café";
    let visits = 3;
    println!("{place}: {visits} visits");
}
```

```javascript
const notes = ["clarity", "care", "craft"];
for (const note of notes) {
  console.log(`Make room for ${note}.`);
}
```

```json
{
  "reading": true,
  "lineLength": 80,
  "theme": "your own"
}
```

## Small comparisons

| Detail | Why it matters | Count |
|:-------|:--------------:|------:|
| Space | Longer descriptions have enough room to wrap without making every other column equally wide. | 120 |
| Color | Distinguish structure while keeping the page comfortable to read. | 8 |
| Navigation | Links reach the intended section, including repeated headings. | 3 |

## A perspective

The first occurrence of a heading gets its natural link.

## A perspective

The [second occurrence](#a-perspective-1) has its own address.

## A second perspective {#perspective}

An explicit address stays useful even when the heading's wording changes.

## Café notes

Unicode belongs in headings, paragraphs, links, and source code. Keep café, 日本語, and 🦀 readable throughout.

## A little HTML

<div>
<p>HTML content can carry <strong>important text</strong>, <em>a gentle aside</em>, <code>inline code</code>, and <a href="#code">a useful link</a>.</p>
<details>
<summary>Notes from the margin</summary>
<p>These details remain available while reading. They contain an explanation that should never silently disappear.</p>
<ul><li>A first observation</li><li>A second observation with <strong>emphasis</strong></li></ul>
</details>
</div>

---

A document can be technically correct and still deserve more care. This is a place to check both.
