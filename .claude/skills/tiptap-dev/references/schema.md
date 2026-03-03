# Tiptap Schema

The schema defines the document structure: which nodes exist, what content they can contain, and which marks can be applied.

## Node Schema Properties

| Property | Type | Description |
|----------|------|-------------|
| `content` | string | Content expression defining allowed children |
| `marks` | string | Allowed marks: `_` (all), `''` (none), `bold italic` |
| `group` | string | Node groups: `block`, `inline`, `list` |
| `inline` | boolean | Is inline node (vs block) |
| `atom` | boolean | Cannot contain content, selected as unit |
| `selectable` | boolean | Can be selected with click |
| `draggable` | boolean | Can be dragged with mouse |
| `defining` | boolean | Content stays when surrounding replaced |
| `isolating` | boolean | Blocks splitting/lifting operations |

## Content Expressions

```typescript
// Content model syntax
content: 'paragraph'           // Single paragraph
content: 'paragraph+'          // One or more paragraphs
content: 'paragraph*'          // Zero or more paragraphs
content: 'paragraph?'          // Zero or one paragraph
content: 'inline*'             // Zero or more inline nodes
content: 'block+'              // One or more block nodes
content: 'text*'               // Zero or more text nodes
content: '(paragraph | heading)+'  // Paragraphs or headings
content: 'paragraph heading'   // Paragraph then heading (sequence)
```

### Common Patterns

```typescript
// Document root
Node.create({
  name: 'doc',
  content: 'block+',
})

// Paragraph with inline content
Node.create({
  name: 'paragraph',
  group: 'block',
  content: 'inline*',
})

// Heading
Node.create({
  name: 'heading',
  group: 'block',
  content: 'inline*',
  defining: true,
})

// List
Node.create({
  name: 'bulletList',
  group: 'block list',
  content: 'listItem+',
})

// List item
Node.create({
  name: 'listItem',
  content: 'paragraph block*',
  defining: true,
})

// Code block (no marks allowed)
Node.create({
  name: 'codeBlock',
  group: 'block',
  content: 'text*',
  marks: '',
})

// Image (atomic, no content)
Node.create({
  name: 'image',
  group: 'block',
  atom: true,
  draggable: true,
  selectable: true,
})
```

## Node Groups

Nodes can belong to multiple groups:

```typescript
// Block node
Node.create({
  name: 'paragraph',
  group: 'block',
})

// Multiple groups
Node.create({
  name: 'bulletList',
  group: 'block list',
})

// Inline node
Node.create({
  name: 'mention',
  group: 'inline',
  inline: true,
})
```

Use groups in content expressions:

```typescript
content: 'block+'    // Any block node
content: 'list+'     // Any list node
content: 'inline*'   // Any inline node
```

## Mark Schema Properties

| Property | Type | Description |
|----------|------|-------------|
| `inclusive` | boolean | Extend mark to new content at edges |
| `excludes` | string | Marks that can't coexist: `_` (all), `''` (none) |
| `spanning` | boolean | Can span multiple nodes |

```typescript
Mark.create({
  name: 'link',
  inclusive: false,  // Don't extend to new text
  excludes: '',      // Can coexist with any mark
  spanning: true,    // Can span multiple nodes
})

Mark.create({
  name: 'code',
  inclusive: true,
  excludes: '_',     // Excludes all other marks
})
```

## Attributes

Define node/mark attributes:

```typescript
Node.create({
  name: 'heading',

  addAttributes() {
    return {
      level: {
        default: 1,
        parseHTML: element => parseInt(element.tagName.charAt(1)),
        renderHTML: attributes => ({}), // Not rendered as HTML attr
      },
    }
  },
})
```

### Attribute Options

```typescript
addAttributes() {
  return {
    myAttr: {
      // Default value
      default: null,

      // Parse from HTML
      parseHTML: element => element.getAttribute('data-my-attr'),

      // Render to HTML
      renderHTML: attributes => {
        if (!attributes.myAttr) return {}
        return { 'data-my-attr': attributes.myAttr }
      },

      // Keep across line breaks
      keepOnSplit: true,

      // Mark as rendered (for DOM diffing)
      rendered: true,
    },
  }
}
```

## Parse Rules

Define how HTML is parsed into nodes:

```typescript
parseHTML() {
  return [
    // Simple tag match
    { tag: 'p' },

    // Tag with attributes
    { tag: 'h1', attrs: { level: 1 } },
    { tag: 'h2', attrs: { level: 2 } },

    // Tag with getter
    {
      tag: 'div[data-type="custom"]',
      getAttrs: element => ({
        myAttr: element.getAttribute('data-my-attr'),
      }),
    },

    // Style match
    { style: 'font-weight=bold' },
    { style: 'font-weight', getAttrs: value => value === 'bold' && null },

    // Priority (higher = earlier)
    { tag: 'strong', priority: 1000 },
  ]
}
```

## Render Rules

Define how nodes render to HTML:

```typescript
renderHTML({ node, HTMLAttributes }) {
  // Array syntax: [tag, attrs, content-hole]
  return ['p', HTMLAttributes, 0]  // 0 = content hole

  // Nested tags
  return ['figure', ['img', HTMLAttributes]]

  // No content hole (atom)
  return ['hr']

  // Custom attributes
  return ['div', mergeAttributes(HTMLAttributes, { class: 'custom' }), 0]
}
```

## Accessing Schema

```typescript
// Get schema from editor
const schema = editor.schema

// Get node type
const paragraphType = schema.nodes.paragraph

// Get mark type
const boldType = schema.marks.bold

// Create node
const node = schema.nodes.paragraph.create(
  { align: 'center' },
  schema.text('Hello')
)

// Create mark
const mark = schema.marks.bold.create()
```
