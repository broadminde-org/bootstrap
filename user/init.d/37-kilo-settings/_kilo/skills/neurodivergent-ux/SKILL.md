---
name: neurodivergent-ux
description: >-
  House standard for neurodivergent-friendly (ADHD, autistic,
  cognitive-accessible) UI/UX design. USE FOR: generating, critiquing, or
  refining any user-facing interface; dashboard and shell layouts; forms and
  multi-step workflows; loading, error, and validation states; choosing
  information density, color, and typography for app UIs. DO NOT USE FOR:
  marketing pages or visual/aesthetic direction (use frontend-design), or
  generic Vercel-style code audits (use web-design-guidelines).
---

# Neurodivergent-Friendly UI/UX Design Guidelines

Apply these guidelines whenever designing, generating, or reviewing user-facing
interfaces. Evaluate every design through an ADHD/autistic/cognitive-accessibility
lens first, then general usability.

## 1. Core Principle: Progressive Disclosure ("Simple Surface, Deep Hood")

- **The Surface:** Interfaces must be clean, minimalist, and low-stimulus.
  Eliminate visual noise, unnecessary decorations, and non-functional animations.
- **The Deep Hood:** Advanced data, complex settings, and technical details must
  never be deleted — only hidden.
- **Implementation:** Use expandable accordions, "Show/Hide Details" toggles, and
  contextual tooltips. Give the user total control over information density
  without overwhelming them by default.

## 2. Executive Function Support & Workflow Flexibility

- **No Linear Traps:** Avoid rigid, multi-step wizards that block the user if they
  skip a step. Allow non-linear data entry wherever possible.
- **State Persistence:** Never clear user input if they navigate away or make a
  mistake. Auto-save everything locally.
- **Visual Anchors:** Clearly mark the current location in a workflow using
  persistent breadcrumbs or progress bars. Avoid relying on memory.
- **Cognitive Load Reduction:** Group related tasks into small, digestible chunks.
  Use clear, descriptive headings instead of ambiguous icons.

## 3. Immediate Feedback Loops

- **System Responsiveness:** Every user action must trigger an immediate visual
  response.
- **Validation:** Provide inline, real-time input validation (e.g., green
  checkmark or descriptive red error text *while* typing, not just upon hitting
  "Submit").
- **Micro-interactions:** Use clear loading skeletons instead of blank screens to
  reduce user anxiety during wait times.

## 4. Visual Layout & Sensory Optimization

- **No Clutter:** Maintain generous whitespace. Ensure a minimum touch target of
  48x48px with clear margins.
- **Color & Contrast:** High contrast for readability, but avoid blindingly bright
  saturated colors or flashing elements. Use muted, calming palettes by default,
  but allow easy theme toggling.
- **Font Hierarchy:** Use clear, highly legible sans-serif fonts. Avoid blocks of
  text longer than three sentences; break information down into punchy, bulleted
  lists.

## 5. Output Format

When generating UI advice, code snippets, or wireframes:

1. Evaluate the design through an ADHD/autistic lens first.
2. Provide a **Simple View** overview.
3. Provide a separate **Technical / Under the Hood** breakdown for advanced
   implementation.

When reviewing existing UI code, report findings as `file:line` references grouped
by the guideline section above (1–4), with a concrete fix for each finding.
