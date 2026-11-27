---
name: neurodivergent-ux
description: >-
  House standard for neurodivergent-friendly (ADHD, autistic,
  cognitive-accessible) UI/UX design. USE FOR: generating, critiquing, or
  refining application interfaces; dashboard and shell layouts; forms and
  multi-step workflows; loading, error, and validation states; choosing
  information density, color, and typography for app UIs. DO NOT USE FOR:
  marketing pages or visual/aesthetic direction (use frontend-design), or
  generic Vercel-style code audits (use web-design-guidelines).
---

# Neurodivergent-Friendly UI/UX Design Guidelines

Apply these guidelines to application interfaces, including interactive app
workflows embedded in a marketing site, not to marketing art direction alone.
Honor the user's design intent and existing design system while protecting
ADHD/autistic/cognitive accessibility and general usability. Accessibility is
not permission to impose a new aesthetic or remove required functionality.

## 1. Core Principle: Progressive Disclosure ("Simple Surface, Deep Hood")

- **The Surface:** Keep the default app surface legible, predictable, and
  low-stimulus within the established design. Reduce distracting decoration and
  non-functional motion; respect reduced-motion preferences.
- **The Deep Hood:** Advanced data, complex settings, and technical details must
  never be deleted — only hidden.
- **Implementation:** Use expandable accordions, "Show/Hide Details" toggles, and
  contextual tooltips. Give the user total control over information density
  without overwhelming them by default.

## 2. Executive Function Support & Workflow Flexibility

- **No Linear Traps:** Avoid rigid, multi-step wizards that block the user if they
  skip a step. Allow non-linear data entry wherever possible.
- **Draft Recovery:** Preserve appropriate non-sensitive input through validation
  errors and accidental navigation using the app's existing recovery mechanism.
  Persistent drafts require informed user consent, an allowlist of non-sensitive
  fields, account/tenant isolation, defined retention/expiry, and visible clear
  controls. Clear drafts on successful submission, explicit discard, logout,
  account switch, and expiry; never restore one account's draft to another.
  Never persist passwords, tokens, payment data, sensitive personal data, or
  ephemeral authentication inputs in browser storage. Use transient state or an
  explicitly approved protected recovery path when appropriate; no universal
  local autosave or new storage subsystem merely for this guideline.
- **Visual Anchors:** Clearly mark the current location in a workflow using
  persistent breadcrumbs or progress bars. Avoid relying on memory.
- **Cognitive Load Reduction:** Group related tasks into small, digestible chunks.
  Use clear, descriptive headings instead of ambiguous icons.

## 3. Immediate Feedback Loops

- **System Responsiveness:** Every user action must trigger an immediate visual
  response.
- **Validation:** Provide descriptive inline feedback at a useful time (such as
  after blur or a completed input), without distracting errors on each keystroke.
  Do not rely on color alone; announce relevant status accessibly without
  flooding live regions.
- **Micro-interactions:** Use clear loading skeletons instead of blank screens to
  reduce user anxiety during wait times.

## 4. Visual Layout & Sensory Optimization

- **No Clutter:** Maintain generous whitespace. Ensure a minimum touch target of
  48x48px with clear margins.
- **Color & Contrast:** High contrast for readability, but avoid blindingly bright
  saturated colors or flashing elements. Use muted, calming palettes by default,
  but allow easy theme toggling.
- **Font Hierarchy:** Prioritize legibility within the user's typography and
  design system. Break long text into meaningful headings and short sections
  without imposing a font-family ban or deleting necessary explanations.

## 5. Output Format

Follow the requested report format. Where none is specified, for substantial UI
advice or wireframes:

1. Evaluate the design through an ADHD/autistic lens first.
2. Provide a **Simple View** overview.
3. Provide a separate **Technical / Under the Hood** breakdown for advanced
   implementation.

When reviewing existing UI code, prioritize findings by severity with `file:line`
references and concrete fixes; guideline sections can label findings but must
not replace the requested review structure. Preserve applicable rendered,
keyboard/focus, accessibility, responsive, and loading/error-state checks;
report unavailable checks rather than treating source review as runtime proof.
