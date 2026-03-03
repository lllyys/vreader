# Tiptap Examples

## Complete Custom Node: Callout Box

```typescript
import { Node, mergeAttributes } from '@tiptap/core'

export const Callout = Node.create({
  name: 'callout',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      type: {
        default: 'info',
        parseHTML: element => element.getAttribute('data-callout-type'),
        renderHTML: attributes => ({ 'data-callout-type': attributes.type }),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-callout]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['div', mergeAttributes(HTMLAttributes, { 'data-callout': '' }), 0]
  },

  addCommands() {
    return {
      setCallout: (type = 'info') => ({ commands }) => {
        return commands.wrapIn(this.name, { type })
      },
      toggleCallout: (type = 'info') => ({ commands }) => {
        return commands.toggleWrap(this.name, { type })
      },
    }
  },

  addKeyboardShortcuts() {
    return {
      'Mod-Shift-c': () => this.editor.commands.toggleCallout(),
    }
  },

  addInputRules() {
    return [
      wrappingInputRule({
        find: /^:::(\w+)?\s$/,
        type: this.type,
        getAttributes: match => ({ type: match[1] || 'info' }),
      }),
    ]
  },
})
```

## Complete Custom Mark: Highlight

```typescript
import { Mark, mergeAttributes, markInputRule, markPasteRule } from '@tiptap/core'

export const Highlight = Mark.create({
  name: 'highlight',

  addOptions() {
    return {
      colors: ['yellow', 'green', 'blue', 'pink'],
      defaultColor: 'yellow',
    }
  },

  addAttributes() {
    return {
      color: {
        default: this.options.defaultColor,
        parseHTML: element => element.getAttribute('data-color') || this.options.defaultColor,
        renderHTML: attributes => ({ 'data-color': attributes.color }),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'mark' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['mark', mergeAttributes(HTMLAttributes), 0]
  },

  addCommands() {
    return {
      setHighlight: (color) => ({ commands }) => {
        return commands.setMark(this.name, { color })
      },
      toggleHighlight: (color) => ({ commands }) => {
        return commands.toggleMark(this.name, { color })
      },
      unsetHighlight: () => ({ commands }) => {
        return commands.unsetMark(this.name)
      },
    }
  },

  addKeyboardShortcuts() {
    return {
      'Mod-Shift-h': () => this.editor.commands.toggleHighlight(),
    }
  },

  addInputRules() {
    return [
      markInputRule({
        find: /(?:==)((?:[^=]+))(?:==)$/,
        type: this.type,
      }),
    ]
  },

  addPasteRules() {
    return [
      markPasteRule({
        find: /(?:==)((?:[^=]+))(?:==)/g,
        type: this.type,
      }),
    ]
  },
})
```

## Extension with Storage

```typescript
import { Extension } from '@tiptap/core'

export const WordCounter = Extension.create({
  name: 'wordCounter',

  addStorage() {
    return {
      wordCount: 0,
      characterCount: 0,
    }
  },

  onCreate() {
    this.updateCounts()
  },

  onUpdate() {
    this.updateCounts()
  },

  addOptions() {
    return {
      onUpdate: () => {},
    }
  },

  updateCounts() {
    const text = this.editor.getText()
    this.storage.characterCount = text.length
    this.storage.wordCount = text.split(/\s+/).filter(word => word.length > 0).length
    this.options.onUpdate({
      words: this.storage.wordCount,
      characters: this.storage.characterCount,
    })
  },
})

// Usage
const editor = useEditor({
  extensions: [
    WordCounter.configure({
      onUpdate: ({ words, characters }) => {
        console.log(`${words} words, ${characters} characters`)
      },
    }),
  ],
})

// Access storage
editor.storage.wordCounter.wordCount
```

## React Node View: Editable Code Block

```typescript
import { Node, mergeAttributes } from '@tiptap/core'
import { ReactNodeViewRenderer, NodeViewWrapper, NodeViewContent } from '@tiptap/react'

function CodeBlockView({ node, updateAttributes, extension }) {
  return (
    <NodeViewWrapper className="code-block">
      <select
        value={node.attrs.language}
        onChange={e => updateAttributes({ language: e.target.value })}
      >
        {extension.options.languages.map(lang => (
          <option key={lang} value={lang}>{lang}</option>
        ))}
      </select>
      <pre>
        <NodeViewContent as="code" />
      </pre>
    </NodeViewWrapper>
  )
}

export const CodeBlock = Node.create({
  name: 'codeBlock',
  group: 'block',
  content: 'text*',
  marks: '',
  code: true,

  addOptions() {
    return {
      languages: ['javascript', 'typescript', 'python', 'rust'],
    }
  },

  addAttributes() {
    return {
      language: { default: 'javascript' },
    }
  },

  parseHTML() {
    return [{ tag: 'pre' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['pre', mergeAttributes(HTMLAttributes), ['code', 0]]
  },

  addNodeView() {
    return ReactNodeViewRenderer(CodeBlockView)
  },

  addKeyboardShortcuts() {
    return {
      'Mod-Alt-c': () => this.editor.commands.toggleCodeBlock(),
    }
  },

  addInputRules() {
    return [
      textblockTypeInputRule({
        find: /^```([a-z]+)?\s$/,
        type: this.type,
        getAttributes: match => ({ language: match[1] }),
      }),
    ]
  },
})
```

## Complete React Editor

```typescript
import { useEditor, EditorContent, BubbleMenu } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Highlight from '@tiptap/extension-highlight'
import Link from '@tiptap/extension-link'

function Toolbar({ editor }) {
  if (!editor) return null

  return (
    <div className="toolbar">
      <button
        onClick={() => editor.chain().focus().toggleBold().run()}
        className={editor.isActive('bold') ? 'active' : ''}
        disabled={!editor.can().toggleBold()}
      >
        Bold
      </button>
      <button
        onClick={() => editor.chain().focus().toggleItalic().run()}
        className={editor.isActive('italic') ? 'active' : ''}
      >
        Italic
      </button>
      <button
        onClick={() => editor.chain().focus().toggleHeading({ level: 1 }).run()}
        className={editor.isActive('heading', { level: 1 }) ? 'active' : ''}
      >
        H1
      </button>
    </div>
  )
}

function Editor({ content, onChange }) {
  const editor = useEditor({
    extensions: [
      StarterKit,
      Highlight,
      Link.configure({
        openOnClick: false,
      }),
    ],
    content,
    onUpdate: ({ editor }) => {
      onChange?.(editor.getHTML())
    },
    immediatelyRender: false,
  })

  return (
    <div className="editor-container">
      <Toolbar editor={editor} />
      {editor && (
        <BubbleMenu editor={editor} tippyOptions={{ duration: 100 }}>
          <button onClick={() => editor.chain().focus().toggleBold().run()}>
            B
          </button>
          <button onClick={() => editor.chain().focus().toggleItalic().run()}>
            I
          </button>
        </BubbleMenu>
      )}
      <EditorContent editor={editor} className="editor-content" />
    </div>
  )
}

export default Editor
```

## Extending StarterKit

```typescript
import StarterKit from '@tiptap/starter-kit'
import { Heading } from '@tiptap/extension-heading'

// Disable specific extensions
StarterKit.configure({
  heading: false,
  codeBlock: false,
})

// Custom heading with limited levels
const CustomHeading = Heading.extend({
  addKeyboardShortcuts() {
    return {
      ...this.parent?.(),
      'Mod-Alt-1': () => this.editor.commands.toggleHeading({ level: 1 }),
      'Mod-Alt-2': () => this.editor.commands.toggleHeading({ level: 2 }),
    }
  },
})

const editor = useEditor({
  extensions: [
    StarterKit.configure({
      heading: false,
    }),
    CustomHeading.configure({
      levels: [1, 2, 3],
    }),
  ],
})
```
