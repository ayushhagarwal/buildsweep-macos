# BuildSweep design system

BuildSweep is always light, including when macOS is in Dark Mode. The main window, Settings, and app-owned sheets use `.preferredColorScheme(.light)` and a shared readable blue tint. The menu-bar extra and native menus keep the system appearance.

Content areas use a near-white canvas and matte cards. Native sidebar materials, toolbars, grouped Settings forms, and standard controls are left in place. Increase Contrast, Reduce Motion, Reduce Transparency, keyboard navigation, and VoiceOver continue to inherit platform behavior.

## Tokens

Semantic sRGB colors live on `BuildSweepTheme`:

- Canvas `#F7F9FC` for main content backgrounds (`AppBackground`).
- Surface `#FFFFFF` for standard cards; emphasized surface `#EAF3FF` for highlighted metrics and the sidebar Pro callout.
- Border `#DCE5EF` and stronger border `#B8C9DD` for decorative card edges. Increase Contrast uses semantic primary strokes instead.
- Accent `#356DB3` for interactive controls, links, progress, and highlighted numbers.
- Accent soft `#DCEBFF` for decorative highlights and pale icon-tile backdrops.
- Hover fill `#EFF4FA` for custom clickable rows.

Normal text uses system `.primary` and `.secondary`. Pastel blue is decorative; the stronger accent is for readable actions. Success, caution, and danger stay green, orange, and red.

Category **fills** are pastel and used only in the storage bar, legend swatches, and onboarding stack dots. Category **foregrounds** are the readable accent for symbols, except History which uses system secondary.

| Category | Decorative fill |
|---|---|
| Overview | `#DCEBFF` |
| Derived Data | `#A8CBF4` |
| Archives | `#B5DFEF` |
| Device Support | `#CCE7F8` |
| Simulators | `#BDCFF0` |
| Caches and Logs | `#9EBCE5` |
| AI Tools | `#B9DCE8` |
| History | `#E8EDF3` |

## Surfaces and components

- `surfaceCard()`: white fill, 16-point continuous corners, 1-point border, no shadow. Emphasized cards use the pale blue fill, stronger border, and a 4% black shadow (radius 8, y 2).
- `IconTile`: tinted SF Symbol on a pale tint background, 10-point corners, no white-on-pastel glyphs, gradients, or colored shadows.
- `InfoChip`: onboarding privacy pills with the standard surface treatment.
- `MetricCard`: same layout as before; emphasized values use solid accent, other values use primary text.

## Native actions

Primary actions use `.borderedProminent`. Toolbar Scan and Review Cleanup stay native toolbar controls. Restore Purchases and similar secondary actions stay links or standard buttons. Destructive roles and cleanup confirmation requirements are unchanged. There is no custom gradient button style.

## Onboarding

Full-bleed two-pane layout: visual stage on the left, copy and actions on the right. The storage stack uses matte white and pale blue slabs with fine borders and faint neutral shadows. The folder step is a static pale blue circle with a readable blue symbol. The scan ring uses a pale track and a solid accent stroke. Step indicators and completion symbols are solid accent, not gradients.

## Typography and motion

- System large title for page headings, rounded bold numerals for storage totals, default system control typography everywhere else.
- Motion is limited to onboarding stack/scan assembly, storage-bar entrance, numeric content transitions, and remaining step changes. All of it is gated by `@Environment(\.accessibilityReduceMotion)`. There is no ambient background animation.

## Icons

SF Symbols for controls and categories; the original app icon uses three build layers plus a sweeping arc. The app icon source and rejected alternatives are preserved in the project-level `design-concepts` handoff folder; the asset catalog contains all required macOS sizes.
