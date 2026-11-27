---
name: frontend-design
description: >-
  Create distinctive, production-grade frontend interfaces with high design
  quality. Use this skill when the user asks to build web components, pages,
  artifacts, posters, or applications (examples include websites, landing pages,
  dashboards, React components, HTML/CSS layouts, or when styling/beautifying
  any web UI). Generates creative, polished code and UI design that avoids
  generic AI aesthetics.
license: Complete terms in LICENSE.txt
metadata:
  category: development
  source:
    repository: 'https://github.com/anthropics/skills'
    path: skills/frontend-design
    license_path: skills/frontend-design/LICENSE.txt
---

This skill guides creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

The user provides frontend requirements: a component, page, application, or interface to build. They may include context about the purpose, audience, or technical constraints.

## Design Precedence

The user's explicit design intent and existing design system take precedence
over this skill's aesthetic suggestions. Preserve established typography,
components, density, and theme unless the task calls for redesign. Do not
require every result to use a new identity. For app workflows, load the
applicable cognitive-accessibility guidance when available; the self-contained
minimum remains legibility/contrast, keyboard access and visible focus,
predictable navigation, reduced-motion support, and clear loading/error states.
Visual novelty never overrides these requirements or removes required content.
Marketing art direction can be expressive without imposing high-stimulus app UI.

## Design Thinking

Before coding, understand the context and choose an intentional direction within
the user's brief and existing design constraints:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Derive it from the brief: editorial, organic, refined, playful, industrial, or another appropriate visual language. Extremes are optional inspiration, not a mandate.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work - the key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Frontend Aesthetics Guidelines

Focus on:
- **Typography**: Preserve established fonts; for a new direction, choose legible body text and appropriate display character. System fonts, Arial, or Inter are valid when the brief/design system calls for them; novelty is not a font-family ban.
- **Color & Theme**: Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.
- **Motion**: Use restrained functional feedback where it helps. Honor reduced-motion preferences, avoid flashing/disorienting effects, and never make content or controls depend on animation, hover, or scroll reveals. Use existing tooling; do not add a motion dependency merely for this skill.
- **Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.
- **Backgrounds & Visual Details**: Create atmosphere and depth rather than defaulting to solid colors. Add contextual effects and textures that match the overall aesthetic. Apply creative forms like gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, and grain overlays.

Avoid interchangeable, context-free styling. Familiar components, readable
fonts, and predictable app navigation are useful, not aesthetic failures.

Interpret the brief creatively without changing an established identity merely
for variation. For new designs, choose theme, typography, and composition for
the context rather than repeating one default aesthetic.

**IMPORTANT**: Use the smallest implementation that satisfies the brief and
quality requirements; visual richness does not require elaborate effects.
Preserve applicable rendered, responsive (desktop/mobile), keyboard/focus,
accessibility, interaction, and loading/error-state checks. A preview or source
inspection is not acceptance; report unavailable required checks explicitly.

Remember: The agent is capable of extraordinary creative work. Don't hold back, show what can truly be created when thinking outside the box and committing fully to a distinctive vision.
