# Render Markdown over the original file buffer

The user wants Markdown to open as a rendered document and switch to editable
source without a second buffer or tab. VSVim retains the source buffer, view
choice, and window geometry; sprite.nvim negotiates and transports document
updates; Sprite parses and renders the document with GPUI. Preview input is
handled before it can reach the hidden source. This preserves Neovim's existing
save, dirty-state, and undo behavior. A scratch preview buffer would break the
one-buffer requirement; a browser would add another UI runtime and input owner.
