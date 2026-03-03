# Tiptap Extensions

Extensions are the building blocks of Tiptap. There are three types:

## Extension Types

### 1. Extension (Functionality)

For adding functionality without schema changes:

```typescript
import { Extension } from '@tiptap/core'

const MyExtension = Extension.create({
  name: 'myExtension',

  addOptions() {
    return {
      myOption: 'default',
    }
  },

  addStorage() {
    return {
      count: 0,
    }
  },

  addKeyboardShortcuts() {
    return {
      'Mod-Shift-x': () => this.editor.commands.myCommand(),
    }
  },

  addCommands() {
    return {
      myCommand: () => ({ commands }) => {
        return commands.insertContent('Hello!')
      },
    }
  },
})
```

### 2. Node (Block Content)

For block-level content like paragraphs, headings, images:

```typescript
import { Node } from '@tiptap/core'

const CustomNode = Node.create({
  name: 'customNode',
  group: 'block',
  content: 'inline*',

  addAttributes() {
    return {
      level: {
        default: 1,
        parseHTML: element => element.getAttribute('data-level'),
        renderHTML: attributes => ({ 'data-level': attributes.level }),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'custom-node' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['custom-node', HTMLAttributes, 0]
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const dom = document.createElement('div')
      // Custom rendering logic
      return { dom }
    }
  },
})
```

### 3. Mark (Inline Formatting)

For inline formatting like bold, italic, links:

```typescript
import { Mark } from '@tiptap/core'

const CustomMark = Mark.create({
  name: 'customMark',

  addAttributes() {
    return {
      color: { default: null },
    }
  },

  parseHTML() {
    return [{ tag: 'span[data-custom-mark]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', { 'data-custom-mark': '', ...HTMLAttributes }, 0]
  },

  addCommands() {
    return {
      setCustomMark: attributes => ({ commands }) => {
        return commands.setMark(this.name, attributes)
      },
      toggleCustomMark: attributes => ({ commands }) => {
        return commands.toggleMark(this.name, attributes)
      },
    }
  },
})
```

## Extending Existing Extensions

Use `extend()` to modify built-in extensions:

```typescript
import { Bold } from '@tiptap/extension-bold'

const CustomBold = Bold.extend({
  // Override keyboard shortcuts
  addKeyboardShortcuts() {
    return {
      'Mod-Shift-b': () => this.editor.commands.toggleBold(),
    }
  },

  // Add new attributes
  addAttributes() {
    return {
      ...this.parent?.(),
      customAttr: { default: null },
    }
  },
})
```

## Extension Configuration

Configure extensions when adding to editor:

```typescript
const editor = new Editor({
  extensions: [
    StarterKit.configure({
      heading: { levels: [1, 2, 3] },
      bold: false, // disable bold
    }),
    CustomExtension.configure({
      myOption: 'value',
    }),
  ],
})
```

## Common Extension Properties

| Property | Description |
|----------|-------------|
| `name` | Unique identifier (required) |
| `group` | Schema group: 'block', 'inline', 'list' |
| `content` | Content model: 'inline*', 'block+', 'text*' |
| `marks` | Allowed marks: '_' (all), '' (none), 'bold italic' |
| `atom` | Cannot contain content, selected as unit |
| `inline` | Inline node (vs block) |
| `draggable` | Can be dragged |
| `selectable` | Can be selected as unit |
| `defining` | Content stays when surrounding replaced |
| `isolating` | Blocks splitting/lifting operations |

## Extension Lifecycle

```typescript
Extension.create({
  onCreate() {
    // Editor created, before first transaction
  },
  onUpdate() {
    // Document changed
  },
  onSelectionUpdate() {
    // Selection changed
  },
  onTransaction({ transaction }) {
    // Any transaction
  },
  onFocus({ event }) {
    // Editor focused
  },
  onBlur({ event }) {
    // Editor blurred
  },
  onDestroy() {
    // Editor destroyed
  },
})
```
