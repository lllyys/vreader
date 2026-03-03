# Tiptap React Integration

## Installation

```bash
npm install @tiptap/react @tiptap/pm @tiptap/starter-kit
```

- `@tiptap/react` - React bindings and hooks
- `@tiptap/pm` - ProseMirror dependencies
- `@tiptap/starter-kit` - Common extensions bundle

## Basic Setup

```typescript
import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'

function Editor() {
  const editor = useEditor({
    extensions: [StarterKit],
    content: '<p>Hello World!</p>',
  })

  return <EditorContent editor={editor} />
}
```

## useEditor Hook

### Configuration Options

```typescript
const editor = useEditor({
  // Required: extensions array
  extensions: [
    StarterKit,
    Highlight,
    Link.configure({ openOnClick: false }),
  ],

  // Initial content (HTML, JSON, or null)
  content: '<p>Initial content</p>',

  // Editable state
  editable: true,

  // Autofocus on mount
  autofocus: true, // or 'start', 'end', number

  // SSR: disable immediate rendering
  immediatelyRender: false,

  // Event callbacks
  onCreate: ({ editor }) => {},
  onUpdate: ({ editor }) => {},
  onSelectionUpdate: ({ editor }) => {},
  onTransaction: ({ editor, transaction }) => {},
  onFocus: ({ editor, event }) => {},
  onBlur: ({ editor, event }) => {},
  onDestroy: () => {},

  // Editor props (ProseMirror)
  editorProps: {
    attributes: {
      class: 'prose prose-sm',
    },
    handleDrop: (view, event, slice, moved) => {},
    handlePaste: (view, event, slice) => {},
  },
})
```

### Accessing Editor

```typescript
function EditorComponent() {
  const editor = useEditor({ ... })

  if (!editor) {
    return null // Editor not yet initialized
  }

  return (
    <div>
      <button onClick={() => editor.chain().focus().toggleBold().run()}>
        Bold
      </button>
      <EditorContent editor={editor} />
    </div>
  )
}
```

## EditorContext

Share editor instance across components:

```typescript
import { EditorContext, EditorContent, useEditor } from '@tiptap/react'

function App() {
  const editor = useEditor({ ... })

  return (
    <EditorContext.Provider value={{ editor }}>
      <Toolbar />
      <EditorContent editor={editor} />
      <WordCount />
    </EditorContext.Provider>
  )
}
```

### useCurrentEditor Hook

Access editor from child components:

```typescript
import { useCurrentEditor } from '@tiptap/react'

function Toolbar() {
  const { editor } = useCurrentEditor()

  if (!editor) return null

  return (
    <div>
      <button
        onClick={() => editor.chain().focus().toggleBold().run()}
        className={editor.isActive('bold') ? 'active' : ''}
      >
        Bold
      </button>
    </div>
  )
}
```

## useEditorState Hook

Subscribe to specific state changes efficiently:

```typescript
import { useEditorState } from '@tiptap/react'

function FormatStatus() {
  const { editor } = useCurrentEditor()

  const state = useEditorState({
    editor,
    selector: ({ editor }) => ({
      isBold: editor.isActive('bold'),
      isItalic: editor.isActive('italic'),
      heading: editor.isActive('heading'),
      headingLevel: editor.getAttributes('heading').level,
    }),
  })

  return (
    <div>
      {state.isBold && <span>Bold</span>}
      {state.isItalic && <span>Italic</span>}
      {state.heading && <span>H{state.headingLevel}</span>}
    </div>
  )
}
```

## Built-in Menu Components

### BubbleMenu

Floating menu on text selection:

```typescript
import { BubbleMenu } from '@tiptap/react'

function Editor() {
  const editor = useEditor({ ... })

  return (
    <>
      <EditorContent editor={editor} />
      <BubbleMenu editor={editor} tippyOptions={{ duration: 100 }}>
        <button onClick={() => editor.chain().focus().toggleBold().run()}>
          Bold
        </button>
        <button onClick={() => editor.chain().focus().toggleItalic().run()}>
          Italic
        </button>
      </BubbleMenu>
    </>
  )
}
```

### FloatingMenu

Menu that appears on empty lines:

```typescript
import { FloatingMenu } from '@tiptap/react'

function Editor() {
  const editor = useEditor({ ... })

  return (
    <>
      <EditorContent editor={editor} />
      <FloatingMenu editor={editor}>
        <button onClick={() => editor.chain().focus().toggleHeading({ level: 1 }).run()}>
          H1
        </button>
        <button onClick={() => editor.chain().focus().toggleBulletList().run()}>
          Bullet List
        </button>
      </FloatingMenu>
    </>
  )
}
```

## React Node Views

Create interactive React components for nodes:

```typescript
import { Node, mergeAttributes } from '@tiptap/core'
import { ReactNodeViewRenderer, NodeViewWrapper, NodeViewContent } from '@tiptap/react'

// React component for the node view
function CounterComponent({ node, updateAttributes }) {
  const increment = () => {
    updateAttributes({ count: node.attrs.count + 1 })
  }

  return (
    <NodeViewWrapper className="counter">
      <span>{node.attrs.count}</span>
      <button onClick={increment}>+</button>
      <NodeViewContent className="content" />
    </NodeViewWrapper>
  )
}

// Node extension with React node view
const Counter = Node.create({
  name: 'counter',
  group: 'block',
  content: 'inline*',

  addAttributes() {
    return { count: { default: 0 } }
  },

  parseHTML() {
    return [{ tag: 'counter' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['counter', mergeAttributes(HTMLAttributes), 0]
  },

  addNodeView() {
    return ReactNodeViewRenderer(CounterComponent)
  },
})
```

### NodeViewWrapper

Required wrapper for React node views. Receives standard DOM props.

### NodeViewContent

Editable content area within node view. Use when `content` is defined.

### Node View Props

```typescript
interface NodeViewProps {
  node: ProseMirrorNode        // The node
  updateAttributes: Function   // Update node attributes
  selected: boolean            // Is selected
  editor: Editor               // Editor instance
  getPos: () => number         // Get node position
  deleteNode: () => void       // Delete this node
  extension: Extension         // The extension
}
```

## TypeScript

```typescript
import { Editor } from '@tiptap/react'

// Type for editor prop
interface Props {
  editor: Editor | null
}

// Type for content
type Content = string | JSONContent | JSONContent[] | null
```

## Performance Tips

1. Use `immediatelyRender: false` for SSR
2. Use `useEditorState` for granular subscriptions
3. Memoize toolbar buttons with `React.memo`
4. Avoid inline function definitions in render
5. Use `editor.can()` for button disabled states
