# OpenStream Apple Design System

## Core Principles
1. **Black-First Appearance**: Emphasize true blacks for deep OLED contrasts.
2. **One Brand Accent**: A vibrant, singular brand color. No system blue defaults.
3. **No Liquid Glass**: Avoid excessive frosted/glass materials. Keep surfaces solid and grounded.

## Color Tokens (AppleDesignTokens.swift)
- **Background**: True Black (`#000000`)
- **Surface**: Dark Gray (`#1C1C1E`)
- **Text Primary**: Pure White (`#FFFFFF`)
- **Text Secondary**: Light Gray (`#EBEBF5` 60% opacity)
- **Brand Accent**: Primary Brand Color (`#FF3366`)

## Typography Scale
- **Large Title**: 34pt, Bold
- **Title 1**: 28pt, Bold
- **Title 2**: 22pt, Bold
- **Headline**: 17pt, Semi-Bold
- **Body**: 17pt, Regular
- **Subheadline**: 15pt, Regular
- **Caption**: 12pt, Medium

## Spacing & Corner Radii
- **Spacing**: 8pt, 16pt, 24pt, 32pt increments.
- **Corner Radii**:
  - Buttons: Fully rounded / capsule (Infinity)
  - Cards: 12pt
  - Large Modals: 16pt

## Component Tokens
### Pill Buttons
- **Primary White**: Solid White background, Black text, capsule shape. Use for primary actions like "Play".
- **Secondary Dark**: Translucent Dark Gray background (or solid `#333333`), White text, capsule shape. Use for secondary actions like "Download" or "My List".

### Card Sizes (Poster 2:3 ratio)
- **Phone**: 100pt x 150pt
- **Tablet**: 150pt x 225pt
- **Apple TV (tvOS)**: 300pt x 450pt

## tvOS Focus Treatment
- Use standard `.focusable()` and `.focused(_:)` with system scaling.
- Active focus items lift and receive a prominent white border/glow or slight scale-up. Do not wrap with custom buttons that break the native Siri Remote focus model. 

*Done / hooks needed: Codex to adopt `AppleDesignTokens` in UI components.*
