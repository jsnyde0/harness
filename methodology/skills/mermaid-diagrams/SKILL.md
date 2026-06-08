---
name: mermaid-diagrams
description: Generate production-ready Mermaid diagrams (flowcharts, sequence diagrams, ER diagrams, state diagrams, C4, architecture, etc.). Use when creating visual representations of systems, workflows, data flows, or any diagrammatic content. Triggers on words like "diagram", "flowchart", "sequence diagram", "visualize", "mermaid".
---

# Mermaid Diagram Generator

Transform textual descriptions, ideas, or malformed Mermaid code into **production-ready, syntactically correct, visually clear Mermaid diagrams**.

## When to Use This Skill

- User asks for a diagram, flowchart, or visualization
- User provides broken/incomplete Mermaid code to fix
- User wants to visualize a system, workflow, or process
- User mentions any Mermaid diagram type (sequence, ER, state, C4, etc.)

## Key Principles

1. **Infer diagram type** from context (flowchart, sequence, ER, state, etc.)
2. **Apply strict syntax** - proper quoting, arrows, node shapes
3. **Use clear layout** - appropriate direction (TD/LR), consistent spacing
4. **Style for readability** - WCAG-compliant colors, clear labels

## Process

1. Read the full reference guide: [reference.md](reference.md)
2. Analyze input to determine diagram type
3. Apply syntax rules from the compendium
4. Output clean Mermaid code block + brief changelog

## Output Format

Always output:
1. A fenced Mermaid code block
2. A brief "Changes:" section (max 5 bullets) noting refinements made

## Quick Reference

Common diagram types (see reference.md for full syntax):
- `flowchart TD/LR` - processes, decisions, workflows
- `sequenceDiagram` - interactions between participants
- `erDiagram` - entity relationships, data models
- `stateDiagram-v2` - state machines
- `classDiagram` - OOP class structures
- `C4Context/C4Container` - system architecture
- `architecture-beta` - infrastructure diagrams
- `mindmap` - hierarchical ideas
- `gantt` - project timelines
