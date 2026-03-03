# Tiptap Commands and API

## Command Chaining

All commands are chainable and must end with `.run()`:

```typescript
// Single command
editor.commands.toggleBold()

// Chained commands
editor.chain()
  .focus()
  .toggleBold()
  .insertContent('Hello')
  .run()
```

## Dry Run with .can()

Check if commands would succeed without executing:

```typescript
// Check if bold can be toggled
const canToggleBold = editor.can().chain().focus().toggleBold().run()

// Useful for button states
<button disabled={!editor.can().toggleBold()}>Bold</button>
```

## Common Commands

### Text Formatting

```typescript
editor.commands.toggleBold()
editor.commands.toggleItalic()
editor.commands.toggleStrike()
editor.commands.toggleCode()
editor.commands.toggleUnderline()
editor.commands.toggleHighlight({ color: '#ffc078' })

// Set/unset marks
editor.commands.setMark('bold')
editor.commands.unsetMark('bold')
editor.commands.unsetAllMarks()
```

### Block Operations

```typescript
editor.commands.toggleHeading({ level: 1 })
editor.commands.toggleBulletList()
editor.commands.toggleOrderedList()
editor.commands.toggleTaskList()
editor.commands.toggleBlockquote()
editor.commands.toggleCodeBlock()
editor.commands.setHorizontalRule()
```

### Content Manipulation

```typescript
// Insert content
editor.commands.insertContent('Hello')
editor.commands.insertContent('<strong>Bold text</strong>')
editor.commands.insertContent({
  type: 'paragraph',
  content: [{ type: 'text', text: 'Hello' }],
})

// Set content (replace all)
editor.commands.setContent('<p>New content</p>')

// Clear content
editor.commands.clearContent()

// Delete selection
editor.commands.deleteSelection()
editor.commands.deleteRange({ from: 0, to: 10 })
```

### Selection

```typescript
editor.commands.focus()
editor.commands.focus('end')
editor.commands.focus('start')
editor.commands.focus('all')
editor.commands.focus(5) // position

editor.commands.selectAll()
editor.commands.setTextSelection({ from: 0, to: 10 })
editor.commands.setNodeSelection(5)
```

### History

```typescript
editor.commands.undo()
editor.commands.redo()
```

### Node Operations

```typescript
// Set node attributes
editor.commands.updateAttributes('heading', { level: 2 })

// Lift/sink nodes
editor.commands.liftListItem('listItem')
editor.commands.sinkListItem('listItem')

// Split/join
editor.commands.splitBlock()
editor.commands.joinBackward()
editor.commands.joinForward()
```

## Creating Custom Commands

```typescript
Extension.create({
  name: 'myExtension',

  addCommands() {
    return {
      // Simple command
      mySimpleCommand: () => ({ commands }) => {
        return commands.insertContent('Hello!')
      },

      // Command with parameters
      myParameterizedCommand: (text: string) => ({ commands }) => {
        return commands.insertContent(text)
      },

      // Command with chain
      myChainedCommand: () => ({ chain }) => {
        return chain()
          .focus()
          .toggleBold()
          .insertContent('Bold text')
          .run()
      },

      // Command with state access
      myStateCommand: () => ({ state, dispatch }) => {
        const { selection, doc } = state
        // Access ProseMirror state
        if (dispatch) {
          // Apply transaction
        }
        return true
      },

      // Command with editor access
      myEditorCommand: () => ({ editor }) => {
        console.log(editor.isActive('bold'))
        return true
      },
    }
  },
})
```

## Editor API

### State Properties

```typescript
editor.isEditable      // Can edit
editor.isEmpty         // No content
editor.isFocused       // Has focus
editor.isDestroyed     // Has been destroyed

editor.state           // ProseMirror EditorState
editor.view            // ProseMirror EditorView
editor.schema          // Document schema
editor.storage         // Extension storage
editor.options         // Editor options
```

### Methods

```typescript
// Content
editor.getHTML()
editor.getJSON()
editor.getText()
editor.getText({ blockSeparator: '\n\n' })

// State checks
editor.isActive('bold')
editor.isActive('heading', { level: 1 })
editor.isActive({ textAlign: 'center' })

// Attributes
editor.getAttributes('heading')
editor.getAttributes('link')

// Lifecycle
editor.destroy()
editor.setEditable(false)
editor.setOptions({ content: 'New' })
```

### Event Handling

```typescript
editor.on('update', ({ editor }) => {
  console.log('Content updated')
})

editor.on('selectionUpdate', ({ editor }) => {
  console.log('Selection changed')
})

editor.on('focus', ({ editor, event }) => {
  console.log('Editor focused')
})

editor.on('blur', ({ editor, event }) => {
  console.log('Editor blurred')
})

// Remove listener
editor.off('update', handler)
```

## Command Context

Commands receive a context object:

| Property | Description |
|----------|-------------|
| `editor` | Editor instance |
| `state` | ProseMirror EditorState |
| `view` | ProseMirror EditorView |
| `dispatch` | Dispatch function (null for can() checks) |
| `chain` | Chainable commands |
| `commands` | All available commands |
| `tr` | Current transaction |
