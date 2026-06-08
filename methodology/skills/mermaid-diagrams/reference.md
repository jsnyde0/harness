# Mermaid Diagram Reference Compendium

Transform ANY textual diagram idea, natural language description, malformed/incomplete Mermaid code, or embedded Mermaid blocks within Markdown into **production-ready, syntactically pristine, visually compelling Mermaid diagrams.**

---
## I. OPERATIONAL PHASES
---

### Phase 1: Input Ingestion & Contextual Analysis
1. **Isolate Mermaid Content:** If input is Markdown, extract content from ` ```mermaid ... ``` ` blocks.
2. **Pre-sanitize:** Normalize whitespace; identify explicit user flags (`theme:`, `type:`, `layout:`).
3. **Diagram Type & Layout Inference:** Determine the most appropriate Mermaid diagram type and layout direction based on flags or content analysis. If ambiguous, default to `flowchart TD`.

### Phase 2: Syntactic & Structural Perfection
1. **Strict Syntax Enforcement:** Apply specific syntax rules for the inferred diagram type:
    - Correct diagram type declaration and direction
    - Proper quoting of identifiers, labels, and text
    - Accurate connection/arrow syntax
    - Valid statement termination and block structuring
2. **Code Formatting:** Consistent indentation and spacing.

### Phase 3: Visual Styling & Clarity Enhancement
1. **Theme & Color Application:**
    - **Default:** WCAG-compliant, clear, professional base theme
    - **User Theme:** Honor `theme: dark | corporate | {JSON_object}`
    - **Specific Styling:** Apply type-specific directives (`style`, `classDef`, etc.)
2. **Layout Optimization:** Refine for balance and legibility.

### Phase 4: Output Assembly
1. Compile the final, validated Mermaid code block.
2. Assemble concise changelog (max 5 refinements).

---
## II. DIAGRAM TYPE INFERENCE MATRIX
---

| Primary Keywords / Structure Cues | Inferred Type | Secondary Cues |
| :--- | :--- | :--- |
| `-->`, `---`, node shapes `[] () (()) {} {{}}`, `subgraph` | `flowchart` | `direction TD/LR`, `style`, `classDef`, `click` |
| `participant`, `actor`, `->>`, `-->>`, `activate`, `loop`, `alt`, `opt`, `par` | `sequenceDiagram` | `autonumber`, `link`, `links` |
| `class`, visibility `+ - # ~`, generics `~Type~`, relations `--|> --* --o` | `classDiagram` | `direction`, `<<annotation>>`, `click` |
| `state`, `[*] -->`, `<<choice>>`, `<<fork>>`, `<<join>>` | `stateDiagram-v2` | `direction LR/TD`, `note` |
| `EntityName { attributes }`, `PK`, `FK`, relations `\|o--o\|` | `erDiagram` | Attribute types, comments |
| `journey`, `section`, `Task: Score: Actor` | `userJourney` | Scores, actors |
| `gantt`, `dateFormat`, `section`, `task: status, id, date, duration` | `gantt` | `crit`, `active`, `done`, `milestone` |
| `pie`, `"Label": value` | `pie` | `showData` |
| `quadrantChart`, `x-axis`, `y-axis`, `quadrant-1/2/3/4` | `quadrantChart` | `radius`, `color` |
| `requirementDiagram`, `requirement { id:, text:, risk: }` | `requirementDiagram` | `satisfies`, `verifies` |
| `gitGraph:`, `commit`, `branch`, `checkout`, `merge` | `gitGraph` | `tag:` |
| `C4Context`/`C4Container`/`C4Component`, `Person()`, `System()`, `Rel()` | `C4...` | `Boundary()`, `UpdateRelStyle()` |
| `mindmap`, indented lists, `::icon()` | `mindmap` | Node shapes |
| `timeline`, `section Year`, `YYYY: event` | `timeline` | Multiple events per period |
| `zenuml`, `@Actor`, `A->B.method()` | `zenuml` | `if/else/opt/par/while` |
| `sankey-beta`, `Source,Target,Value` | `sankey-beta` | CSV-like format |
| `xychart-beta`, `bar [...]`, `line [...]` | `xychart-beta` | `horizontal` |
| `block-beta`, `columns N`, nested `block:name` | `block-beta` | Connections, `classDef` |
| `packet-beta`, byte ranges `0-7: "Label"` | `packet-beta` | 32-bit rows |
| `kanban`, column titles, indented tasks | `kanban` | `@{priority: High}` |
| `architecture-beta`, `service`, `group`, `junction` | `architecture-beta` | `L/R/T/B` sides |
| `radar-beta`, `axis`, `curve` | `radar-beta` | `graticule polygon/circle` |

---
## III. SYNTAX REFERENCE BY DIAGRAM TYPE
---

### 1. Flowcharts (`flowchart`)

**Declaration:** `flowchart <direction>` (TD, TB, BT, LR, RL)

**Nodes:**
- Rectangle: `id[Text]`
- Rounded: `id(Text)`
- Stadium: `id([Text])`
- Subroutine: `id[[Text]]`
- Cylindrical: `id[(Text)]`
- Circle: `id((Text))`
- Asymmetric: `id>Text]`
- Diamond: `id{Text}`
- Hexagon: `id{{Text}}`
- Parallelogram: `id[/Text/]` or `id[\Text\]`

**Connections:**
- Line: `A --- B`
- Arrow: `A --> B`
- With text: `A -- Text --> B`
- Dotted: `A -.- B`, `A -.-> B`
- Thick: `A === B`, `A ==> B`
- Two-way: `<-->`, `o--o`, `x--x`
- Chain: `A --> B --> C`
- Split: `A --> B & C`

**Subgraphs:**
```
subgraph id ["Title"]
    direction LR
    A --> B
end
```

**Styling:**
- `style nodeId fill:#f9f,stroke:#333`
- `classDef className fill:#f9f`
- `nodeId:::className`

**Comments:** `%% comment`

### 2. Sequence Diagrams (`sequenceDiagram`)

**Participants:**
- `participant Name` or `participant Alias as "Name"`
- `actor Name`

**Messages:**
- Solid arrow: `A->>B: Message`
- Dotted arrow: `A-->>B: Reply`
- Solid line: `A->B: Text`
- Dotted line: `A-->B: Text`
- Cross: `A-xB: Lost`
- Open arrow: `A-)B: Async`

**Activations:**
- `activate P` / `deactivate P`
- Inline: `A->>+B: Start` / `B-->>-A: End`

**Control Flow:**
- `loop Text ... end`
- `alt Condition ... else Other ... end`
- `opt Optional ... end`
- `par Action1 ... and Action2 ... end`

**Notes:**
- `note left of P: Text`
- `note right of P: Text`
- `note over P1,P2: Text`

**Autonumbering:** `autonumber`

### 3. Class Diagrams (`classDiagram`)

**Declaration:** `classDiagram` with optional `direction LR`

**Class Definition:**
```
class ClassName {
    +publicAttr: Type
    -privateAttr: Type
    #protectedAttr: Type
    +publicMethod(): ReturnType
    -privateMethod()*
    +staticMethod()$
}
```

**Relationships:**
- Inheritance: `Parent <|-- Child`
- Composition: `Whole --* Part`
- Aggregation: `Container --o Element`
- Association: `A --> B` or `A -- B`
- Dependency: `A ..> B`
- Realization: `Interface <|.. Implementation`

**Cardinality:** `A "1" -- "0..*" B : label`

### 4. State Diagrams (`stateDiagram-v2`)

**Declaration:** `stateDiagram-v2` with optional `direction LR`

**States:**
- Simple: `StateName`
- With description: `StateName : Description`
- Start/End: `[*]`

**Transitions:** `State1 --> State2 : Event`

**Composite States:**
```
state "Name" as S {
    Inner1 --> Inner2
}
```

**Special States:**
- Choice: `state Name <<choice>>`
- Fork: `state Name <<fork>>`
- Join: `state Name <<join>>`

**Concurrency:** Use `--` to separate regions

### 5. Entity Relationship Diagrams (`erDiagram`)

**Entities:**
```
ENTITY {
    type attrName PK "comment"
    type attrName FK
}
```

**Relationships:**
- `||` exactly one
- `|o` zero or one
- `}|` one or more
- `}o` zero or more

**Example:** `CUSTOMER ||--o{ ORDER : places`

### 6. Gantt Charts (`gantt`)

**Configuration:**
```
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    axisFormat %b %d
```

**Tasks:**
- `Task Name: status, id, start, duration`
- Status: `done`, `active`, `crit`
- Duration: `5d`, `3w`, `12h`
- Dependency: `after taskId`

**Milestones:** `Milestone: milestone, m1, 2023-01-10, 0d`

### 7. C4 Diagrams

**Types:** `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`

**Elements:**
- `Person(alias, "Label", "Description")`
- `System(alias, "Label", "Description")`
- `System_Ext(alias, "Label", "Description")`
- `Container(alias, "Label", "Tech", "Description")`
- `ContainerDb(alias, "Label", "Tech", "Description")`
- `Component(alias, "Label", "Tech", "Description")`

**Boundaries:**
```
Container_Boundary(alias, "Label") {
    Component(...)
}
```

**Relationships:** `Rel(from, to, "Label", "Tech")`

### 8. Architecture Diagrams (`architecture-beta`)

**Elements:**
- `service id(icon)["Label"]`
- `group id(icon)["Label"]`
- `junction id`

**Nesting:** `service id in groupId`

**Connections:** `id1:SIDE --> SIDE:id2 ["Label"]`
- Sides: `L`, `R`, `T`, `B`

### 9. Mind Maps (`mindmap`)

**Structure:** Indentation-based hierarchy

**Node Shapes:**
- Default (rounded rectangle)
- `[Square]`
- `(Rounded)`
- `((Circle))`
- `))Bang((`
- `)Cloud(`
- `{{Hexagon}}`

**Icons:** `::icon(fa fa-book)`

### 10. Other Diagram Types

**Pie:** `pie` with `"Label": value` pairs

**Timeline:** `timeline` with `section` and `Date: Event`

**Quadrant:** `quadrantChart` with axes and `Point: [x, y]`

**Sankey:** `sankey-beta` with `Source,Target,Value` rows

**XY Chart:** `xychart-beta` with `bar [...]` and `line [...]`

**Kanban:** Column titles with indented tasks

**Radar:** `radar-beta` with `axis` and `curve` definitions

---
## IV. OUTPUT FORMAT
---

Always output:

1. **Mermaid Code Block:**
```mermaid
[Generated diagram code]
```

2. **Changes:** (Max 5 bullets)
- Key refinement 1
- Key refinement 2
- ...
