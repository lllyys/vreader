# Tiptap Input Rules and Paste Rules

## Input Rules

Input rules trigger transformations as users type, enabling Markdown-like shortcuts.

### Adding Input Rules

```typescript
import { Extension } from '@tiptap/core'
import { markInputRule, nodeInputRule } from '@tiptap/core'

Extension.create({
  name: 'myExtension',

  addInputRules() {
    return [
      // Rules defined here
    ]
  },
})
```

### markInputRule

Apply marks based on text patterns:

```typescript
import { markInputRule } from '@tiptap/core'

// Bold with **text**
markInputRule({
  find: /(?:\*\*)((?:[^*]+))(?:\*\*)$/,
  type: this.type, // or schema.marks.bold
})

// Highlight with ==text==
markInputRule({
  find: /(?:==)((?:[^=]+))(?:==)$/,
  type: this.type,
  getAttributes: match => {
    return { color: 'yellow' }
  },
})
```

### nodeInputRule

Insert or transform nodes based on patterns:

```typescript
import { nodeInputRule } from '@tiptap/core'

// Horizontal rule with ---
nodeInputRule({
  find: /^(?:---|—-|___\s|\*\*\*\s)$/,
  type: this.type,
})

// Image with ![alt](src "title")
nodeInputRule({
  find: /!\[(.+|:?)]\((\S+)(?:(?:\s+)["'](\S+)["'])?\)$/,
  type: this.type,
  getAttributes: match => {
    const [, alt, src, title] = match
    return { src, alt, title }
  },
})
```

### textInputRule

Replace text patterns with other text:

```typescript
import { textInputRule } from '@tiptap/core'

// Replace (c) with ©
textInputRule({
  find: /\(c\)$/,
  replace: '©',
})

// Replace -> with →
textInputRule({
  find: /->$/,
  replace: '→',
})
```

### wrappingInputRule

Wrap content in a block node:

```typescript
import { wrappingInputRule } from '@tiptap/core'

// Blockquote with > at start
wrappingInputRule({
  find: /^>\s$/,
  type: this.type,
})

// Bullet list with - at start
wrappingInputRule({
  find: /^\s*([-+*])\s$/,
  type: this.type,
})
```

## Paste Rules

Paste rules transform content when pasted into the editor.

### Adding Paste Rules

```typescript
Extension.create({
  name: 'myExtension',

  addPasteRules() {
    return [
      // Rules defined here
    ]
  },
})
```

### markPasteRule

Apply marks to pasted content:

```typescript
import { markPasteRule } from '@tiptap/core'

// Highlight ==text== when pasted
markPasteRule({
  find: /(?:==)((?:[^=]+))(?:==)/g, // Note: global flag
  type: this.type,
})

// Bold **text** when pasted
markPasteRule({
  find: /(?:\*\*)((?:[^*]+))(?:\*\*)/g,
  type: this.type,
})
```

### nodePasteRule

Insert nodes from pasted content:

```typescript
import { nodePasteRule } from '@tiptap/core'

// Image from markdown syntax
nodePasteRule({
  find: /!\[(.*?)\]\((.*?)(?:\s+"(.*?)")?\)/g,
  type: this.type,
  getAttributes: match => {
    const [, alt, src, title] = match
    return { src, alt, title }
  },
})

// Video from URL pattern
nodePasteRule({
  find: /https:\/\/(?:www\.)?youtube\.com\/watch\?v=([a-zA-Z0-9_-]+)/g,
  type: this.type,
  getAttributes: match => {
    const [, videoId] = match
    return { src: `https://youtube.com/embed/${videoId}` }
  },
})
```

## Configuration Options

Both input and paste rules accept these options:

| Option | Type | Description |
|--------|------|-------------|
| `find` | RegExp | Pattern to match |
| `type` | MarkType/NodeType | Mark or node type to apply |
| `getAttributes` | Function | Extract attributes from match |
| `undoable` | boolean | Can be undone (input rules, default: true) |

## Common Patterns

### Heading Input Rule

```typescript
// # Heading 1
textblockTypeInputRule({
  find: /^(#{1,6})\s$/,
  type: this.type,
  getAttributes: match => ({
    level: match[1].length,
  }),
})
```

### Code Block Input Rule

```typescript
// ```language
textblockTypeInputRule({
  find: /^```([a-z]+)?\s$/,
  type: this.type,
  getAttributes: match => ({
    language: match[1],
  }),
})
```

### Link Paste Rule

```typescript
// Auto-link URLs when pasted
markPasteRule({
  find: /https?:\/\/[^\s]+/g,
  type: this.type,
  getAttributes: match => ({
    href: match[0],
  }),
})
```

## Tips

1. Use `$` at end of regex for input rules (match at cursor position)
2. Use `g` flag for paste rules (match multiple occurrences)
3. Capture groups in regex accessible via `match[1]`, `match[2]`, etc.
4. Return `false` from `getAttributes` to skip the transformation
