# vmark Code Examples

Real examples from the vmark codebase demonstrating Tiptap API patterns.

## Block Type Commands

### From `blockListHandlers.ts`

```typescript
// Set block types based on type parameter
switch (type) {
  case "paragraph":
    editor.commands.setParagraph();
    break;
  case "heading":
    const level = args.level as number ?? 1;
    editor.commands.setHeading({ level: level as 1 | 2 | 3 | 4 | 5 | 6 });
    break;
  case "codeBlock":
    const language = args.language as string | undefined;
    editor.commands.setCodeBlock(language ? { language } : undefined);
    break;
  case "blockquote":
    editor.commands.setBlockquote();
    break;
}
```

### Toggle Block Types

```typescript
// Toggle patterns with special handling for blockquote
switch (type) {
  case "paragraph":
    editor.commands.setParagraph();
    break;
  case "heading":
    editor.commands.toggleHeading({ level: level as 1 | 2 | 3 | 4 | 5 | 6 });
    break;
  case "codeBlock":
    editor.commands.toggleCodeBlock();
    break;
  case "blockquote":
    // Blockquote needs active check for toggle
    if (editor.isActive("blockquote")) {
      editor.commands.lift("blockquote");
    } else {
      editor.commands.setBlockquote();
    }
    break;
}
```

## List Operations

### From `blockListHandlers.ts`

```typescript
// Toggle lists
switch (type) {
  case "bulletList":
    editor.commands.toggleBulletList();
    break;
  case "orderedList":
    editor.commands.toggleOrderedList();
    break;
}

// Insert horizontal rule
editor.commands.setHorizontalRule();

// List indentation
editor.commands.sinkListItem("listItem");  // Indent
editor.commands.liftListItem("listItem");  // Outdent
```

## Format Operations

### From `formatHandlers.ts`

```typescript
// Toggle marks with focus chain
switch (mark) {
  case "underline":
    editor.chain().focus().toggleMark("underline").run();
    break;
  case "highlight":
    editor.chain().focus().toggleMark("highlight").run();
    break;
}
```

## Heading Level Cycling

### From `wysiwygAdapter.ts`

```typescript
// Decrease heading level (make bigger heading)
const currentLevel = editor.getAttributes("heading").level as number | undefined;
if (!currentLevel) {
  // Not a heading - make it h6
  editor.chain().focus().setHeading({ level: 6 }).run();
} else if (currentLevel > 1) {
  editor.chain().focus().setHeading({ level: (currentLevel - 1) as 1 | 2 | 3 | 4 | 5 }).run();
}

// Increase heading level (make smaller heading)
if (!currentLevel) {
  // Already paragraph, do nothing
} else if (currentLevel < 6) {
  editor.chain().focus().setHeading({ level: (currentLevel + 1) as 2 | 3 | 4 | 5 | 6 }).run();
} else {
  // h6 -> paragraph
  editor.chain().focus().setParagraph().run();
}
```

## Table Operations

### From `useTiptapTableCommands.ts`

```typescript
// Insert table
editor.chain().focus().insertTable({ rows: 2, cols: 2, withHeaderRow: true }).run();
```

## Document Content Operations

### From `documentHandlers.ts`

```typescript
// Set entire document content
editor.commands.setContent(parsedDoc.toJSON(), { emitUpdate: false });

// Insert at cursor
editor.commands.insertContent(parsedDoc.content.toJSON());

// Insert at specific position
editor.commands.insertContentAt(position, parsedDoc.content.toJSON());
```

### From `TiptapEditor.tsx`

```typescript
// Update content without triggering update events
editor.commands.setContent(doc, { emitUpdate: false });
```

## Code Block Language

### From `codeBlockLineNumbers/tiptap.ts`

```typescript
// Update code block language attribute
this.editor.chain().focus().updateAttributes("codeBlock", { language: langId }).run();
```

## Editor Control

### From `editorHandlers.ts`

```typescript
// Undo/Redo
editor.commands.undo();
editor.commands.redo();
```

## Selection and Cursor

### From `cursorHandlers.ts`

```typescript
// Set cursor position
editor.commands.setTextSelection(position);

// Get current selection
const { from, to } = editor.state.selection;
```

## State Checking Examples

### From `editorPlugins.tiptap.ts`

```typescript
// Check if inside blockquote
if (editor.isActive("blockquote")) {
  // Handle blockquote-specific behavior
}
```

## Anti-Pattern: Losing Block Boundaries

### Current Issue in `cursorHandlers.ts`

```typescript
// WRONG - This loses block structure
const text = doc.textContent;
let lineStart = from;
while (lineStart > 0 && text[lineStart - 1] !== "\n") lineStart--;

// BETTER - Use $pos for block-aware traversal
const $pos = doc.resolve(from);
const blockNode = $pos.parent;
const blockStart = $pos.before($pos.depth);
const blockEnd = $pos.after($pos.depth);
const blockText = blockNode.textContent;
```

## Multi-Selection Patterns

### From `wysiwygMultiSelection.ts`

```typescript
// Handle multi-selection heading toggle
if (level === 0) {
  editor.chain().focus().setParagraph().run();
} else {
  editor.chain().focus().setHeading({ level: level as 1 | 2 | 3 | 4 | 5 | 6 }).run();
}
```
