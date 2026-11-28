---
name: theme-factory
description: >-
  Apply or select a consistent font/color theme for slides, documents, reports,
  HTML artifacts, or landing pages when theme styling is requested. Reuse a
  selected theme or existing design system; choose from ten bundled themes or
  create a custom theme within the requested scope.
license: Complete terms in LICENSE.txt
metadata:
  category: creative-media
  source:
    repository: 'https://github.com/ComposioHQ/awesome-claude-skills'
    path: theme-factory
    license_path: theme-factory/LICENSE.txt
---


# Theme Factory Skill

Bootstrap customization (2026-11-23): scoped selection/reuse, export authority, and accessibility guidance; original theme assets and licenses retained.

This skill provides ten font/color themes for requested artifact styling. Existing design systems, user choices, and applicable accessibility requirements take precedence over a preset.

## Purpose

Use for theme selection or application to slides, documents, reports, and HTML artifacts, not an unsolicited redesign. Each theme includes:
- A cohesive color palette with hex codes
- Complementary font pairings for headers and body text
- A distinct visual identity suitable for different contexts and audiences

## Usage Instructions

To apply styling to a slide deck or other artifact:

1. Reuse the theme already selected for this workstream or the existing design system without another showcase/confirmation turn.
2. If the user requests options, show the unchanged `theme-showcase.pdf` when a permitted viewer is available, or describe relevant options. Ask for selection only when their choice is actually needed; if selection is delegated, choose a suitable theme and state it briefly.
3. Read only the selected theme's specification and apply it within the existing artifact workflow. Theme application does not require regeneration, bundling, packaging, or an extra finalization step; export only when requested and authorized.

## Themes Available

The following 10 themes are available, each showcased in `theme-showcase.pdf`:

1. **Ocean Depths** - Professional and calming maritime theme
2. **Sunset Boulevard** - Warm and vibrant sunset colors
3. **Forest Canopy** - Natural and grounded earth tones
4. **Modern Minimalist** - Clean and contemporary grayscale
5. **Golden Hour** - Rich and warm autumnal palette
6. **Arctic Frost** - Cool and crisp winter-inspired theme
7. **Desert Rose** - Soft and sophisticated dusty tones
8. **Tech Innovation** - Bold and modern tech aesthetic
9. **Botanical Garden** - Fresh and organic garden colors
10. **Midnight Galaxy** - Dramatic and cosmic deep tones

## Application Process

After a preferred theme is selected:
1. Read the corresponding theme file from the `themes/` directory
2. Apply the specified colors and fonts consistently throughout the deck
3. Check contrast for actual foreground/background pairings and readability; palettes are not prequalified accessible combinations. Use available fonts/fallbacks without silently fetching or installing fonts.
4. Maintain the theme's visual identity across all slides

## Create your Own Theme
When requested or delegated selection has no suitable preset, define a named custom palette and font pairing from the brief and apply it in the same workflow. Seek review only when the user reserves that decision or a material ambiguity blocks application. Do not write a new reusable theme file or distribution package unless requested. Retain the artifact's applicable rendered, accessibility, and responsive checks; theme selection alone is not acceptance evidence.
