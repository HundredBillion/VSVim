# Markdown preview

Read this document, then click **Open Markdown Source** to edit it. Click the
**eye** to return to the preview. Both views share one file and undo history.

## A document, rendered

A paragraph with **strong text**, *emphasis*, ~~strikethrough~~, and `inline code`.
Follow an [external link](https://example.com), jump to [the checklist](#checklist),
or open the [VSVim README](../../README.md).

> The original Markdown stays in the editor buffer, including unsaved edits.

### Checklist

- [x] Open Markdown in preview
- [x] Switch to source in the same buffer
- [ ] Add an unsaved sentence and preview it

1. Edit the source.
2. Preview the changes.
3. Undo the edit after returning to source.

| View | Button | File |
| --- | --- | --- |
| Preview | File code | Original buffer |
| Source | Eye | Original buffer |

```lua
local document = "One buffer, two views"
print(document)
```

---

Unicode: café, 日本語, Ελληνικά, 👁.

![A missing image keeps its alternative text](missing-image.png)
