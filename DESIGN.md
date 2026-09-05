---
version: alpha
name: "AutoMAA"
description: "A calm, native macOS control surface for configuring and supervising MAA workflows."
colors:
  primary: "#007D78"
  primary-dark: "#4FCCC2"
  info: "#217AF0"
typography:
  sans:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"
  mono:
    fontFamily: "'SF Mono', ui-monospace, monospace"
rounded:
  DEFAULT: "0.5625rem"
  sm: "0.5rem"
  md: "0.625rem"
  lg: "0.875rem"
spacing:
  control-gap: "0.5625rem"
  card-gap: "0.875rem"
  section-gap: "1.25rem"
  page-inset: "1.75rem"
  page-max: "66.25rem"
  reading-max: "56.25rem"
components:
  button:
    textColor: "{colors.primary}"
  panel:
    rounded: "{rounded.lg}"
  task-card:
    textColor: "{colors.primary}"
  accent-dark:
    textColor: "{colors.primary-dark}"
  field:
    rounded: "{rounded.DEFAULT}"
  app-background:
    backgroundColor: "{colors.info}"
  status: { }
  dialog: { }
---

# AutoMAA Design System

## Overview

### Creative North Star

AutoMAA should feel like a well-organized macOS utility inspector: a quiet control desk where the current state, the next action, and any safety issue are visible without decorative competition. The product may acknowledge the game domain through task names and SF Symbols, but its visual register stays closer to System Settings and a native operations console than to a game launcher.

### Product context and register

- **Audience and primary job:** MAA users who configure recurring workflows across clients and accounts, then need to verify readiness, observe progress, and intervene safely when necessary.
- **Target market(s) and evidence:** The shipped UI and user documentation are Simplified Chinese. Supported game servers do not by themselves establish additional market-specific visual conventions.
- **Locale(s) and language policy:** User-facing product copy is concise Simplified Chinese. Protocol names, paths, identifiers, and upstream MAA terms remain in their canonical form when translation would reduce precision.
- **Usage scene:** Desktop macOS use, often during setup or diagnosis, with moderately dense forms and repeated status checks. Safety and scanability have priority over promotional expression.
- **Register:** Product utility throughout the application; the About and documentation entry points may carry slightly more brand expression.
- **Memorable signature:** Teal `primary` marks runnable actions, active tasks, and selected operational state inside restrained material panels.
- **Restraint:** Forms, scheduling, destructive actions, warnings, and progress use familiar native controls and stable geometry.
- **Anti-references:** Avoid anime artwork, neon gaming dashboards, glass-heavy launchers, and generic web-admin chrome. They obscure operational hierarchy or conflict with the native macOS context.
- **Token ownership/runtime mapping:** This document mirrors the canonical SwiftUI implementation in `Sources/AutoMAA/Theme.swift` and the shared views that consume it. Runtime values remain owned by SwiftUI and macOS semantic colors; review and design lint are the drift gates.

## Colors

`primary` is the product accent for selection, active task iconography, and constructive actions. `info` is reserved for informational emphasis where a second cool hue is useful. Success, warning, and danger use the corresponding macOS semantic colors; they must not be repurposed for decoration or replaced with fixed light-mode values.

The accent adapts through the named AppKit color in `Theme.swift`: a deeper teal for light surfaces and a brighter teal for dark surfaces. Prominent actions use the deep `maaAction` fill in both appearances to retain contrast with their white labels. Selected weekday controls use primary text on a tinted surface; white text is not hand-painted on teal. Overview counts remain neutral, so warning and error colors retain operational meaning.

Panels, labels, dividers, and text rely on SwiftUI semantic colors and materials so light mode, dark mode, increased contrast, and system appearance remain correct. Borders use low-opacity primary text rather than a fixed light-only gray. Status is never communicated by color alone: symbols or text accompany every important state.

## Typography

The interface uses the macOS system family through SwiftUI text styles. Titles and section labels use native weight changes instead of separate display typefaces. Body and caption text remain readable in Simplified Chinese and mixed Chinese/Latin strings through the system fallback stack.

Technical values, stage names, percentages, and counters may use `mono` or monospaced digits when alignment or exact comparison matters. Controls use sentence-style Chinese labels; all-caps styling and decorative italics are avoided.

## Layout

Primary editors use a centered content column capped at `page-max` with `page-inset` padding. Sections follow `section-gap`; related task cards use an adaptive grid with a 21.25rem minimum width and `card-gap`, allowing one column before content becomes cramped.

`PageLayout` and `AppPage` own the shared 28-point inset and 20-point section gap. Overview and plan editing use the 1060-point column; client/account editing, activity, settings and About use a 900-point reading column. Step order and account choices wrap into adaptive grids.

Forms preserve label/control relationships with native `Picker`, `Toggle`, `Stepper`, `DatePicker`, and `TextField` behavior. Optional or conditional settings appear directly below their controlling choice. Loading, validation, and saved state must not change the width or position of the primary action.

## Elevation & Depth

Hierarchy comes from macOS regular material, a one-pixel semantic border, and tonal grouping. Panels do not stack arbitrary shadows. Modal confirmation and system pickers use native elevation. Dark mode keeps the same hierarchy through materials and semantic opacity instead of a second hand-tuned palette.

## Shapes

Large panels use `lg`; compact groups use `md`; editable fields use `DEFAULT`; task icon containers and small chips use `sm`. Corners remain continuous where SwiftUI supports them. Dividers and one-pixel strokes separate dense content; pills are limited to status or genuinely compact categorical controls.

## Components

### Foundational visual states

Default state uses primary text and native control styling. Hover, pressed, focus, and keyboard focus remain system-defined. Selected state uses `primary` plus a label or icon. Disabled content stays visible at reduced opacity and cannot be mistaken for loading. Success, warning, and error use semantic color with explicit copy. Busy work uses native `ProgressView`; skeletons are not part of the application language.

### Buttons and actions

`SectionHeading`, `EntityIcon`, `SettingsToggleRow`, `StatusBadge`, `ReorderButtons` and `DetailDisclosure` in `InterfaceComponents.swift` own repeated page, heading, switch, status, ordering and detail treatments. Native button styles define ordinary actions. The principal run action is visually prominent and stable in size. Destructive actions use the destructive role and remain separated from constructive actions. Icon-only buttons require a help label and accessibility label.

### Navigation and data display

The macOS sidebar is the persistent navigation model. Panels organize dashboards and editors; activity records use structured rows and expandable details. Selected and running plans are distinct states in both copy and color. Dense values use aligned digits, not oversized KPI decoration.

### Forms and overlays

Data entry uses native controls and keeps validation near the affected setting. A controlling strategy choice precedes its conditional fields. Confirmation dialogs are reserved for destructive or consequential actions. Banners summarize save and run results in a bounded overlay; details remain in readiness or activity views. Banner and editable-name transitions respect Reduce Motion. Shared behavior and native-control ownership are documented in [UX-CONTRACT.md](UX-CONTRACT.md).

### Update behavior

`UpdateProgressRow` owns pending update feedback in Settings: native indeterminate progress, named stage, elapsed time, the shared limit from `UpdatePolicy`, and a consistently labeled “取消更新” action. Automatic and manual work use the same controls. Cancellation remains busy until cleanup finishes; errors remain beside the owning update action and in MAA activity history. `AppModel.startMAAUpdate` owns both automatic and manual MAA task lifecycle. `WorkflowRunner` owns staged validation and activation; the UI never infers compatibility.

“更新 MAA” includes the engine and recognition data; “仅更新识别数据” synchronizes separately published data without replacing the engine. Beta remains an explicit native confirmation. SwiftUI/macOS own focus, menus, semantic colors and scrolling; these native variants also apply to update controls.

### Iconography

Use SF Symbols. Filled task symbols are acceptable inside the 2rem task container; ordinary action symbols follow the native rendering mode. Symbols support text rather than replace it for consequential actions.

### Motion

Motion communicates focus or state transitions and stays short, typically around 140ms for local feedback. Animations must be interruptible and respect Reduce Motion. Avoid continuous decorative animation.

### Content and data visualization

Product voice is direct, specific, and actionable. State copy says what happened and what the user can do next. Times use the user's locale and 24-hour scheduling presentation already established by the app. Counts and percentages use monospaced digits when they update in place. There is no chart palette until a data visualization is introduced with an accessible textual alternative.

## Do's and Don'ts

- **Do:** Keep safety checks, remembered state, and the next recovery action visible beside the setting they affect.
- **Do:** Reuse native controls, semantic colors, `Panel`, and established spacing before introducing a new component.
- **Don't:** Add game-themed decoration, gradients, or animated chrome to routine configuration surfaces.
- **Don't:** hide errors behind color-only state, transient hover, or layout-shifting banners.
