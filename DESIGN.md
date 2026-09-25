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

`PageLayout` and `AppPage` own the shared 28-point inset and 20-point section gap. Overview and plan editing use the 1060-point column; client/account editing, activity, settings and About use a 900-point reading column. Account and schedule settings share an adaptive row; step order uses a compact summary with a full-row disclosure for reordering. Fight settings occupy the full column at their position in the execution order, while consecutive shorter task cards keep the adaptive grid.

Forms preserve label/control relationships with native `Picker`, `Toggle`, `Stepper`, `DatePicker`, and `TextField` behavior. Optional or conditional settings appear directly below their controlling choice. Loading, validation, and saved state must not change the width or position of the primary action.

## Elevation & Depth

Hierarchy comes from macOS regular material, a one-pixel semantic border, and tonal grouping. Panels do not stack arbitrary shadows. Modal confirmation and system pickers use native elevation. Dark mode keeps the same hierarchy through materials and semantic opacity instead of a second hand-tuned palette.

## Shapes

Large panels use `lg`; compact groups use `md`; editable fields use `DEFAULT`; task icon containers and small chips use `sm`. Corners remain continuous where SwiftUI supports them. Dividers and one-pixel strokes separate dense content; pills are limited to status or genuinely compact categorical controls.

## Components

### Foundational visual states

Default state uses primary text and native control styling. Native buttons own pressed and keyboard activation; the shared disclosure header adds a quiet hover surface and a visible focus outline. Selected state uses `primary` plus a label or icon. Disabled actions stay visible at reduced opacity. Disabled task cards retain only their title and enable switch; saved parameters reappear when enabled. Success, warning, and error use semantic color with explicit copy. Busy work uses native `ProgressView`; skeletons are not part of the application language.

### Buttons and actions

`SectionHeading`, `EntityIcon`, `SettingsToggleRow`, `StatusBadge`, `ReorderButtons` and `DetailDisclosure` in `InterfaceComponents.swift` own repeated page, heading, switch, status, ordering and detail treatments. Native button styles define ordinary actions. Action menus, including split buttons with a primary action, use `fixedSize(horizontal: true, vertical: false)` to size their trigger to its label and indicator; spacers own the remaining row width, while macOS owns popup sizing and keyboard behavior. The principal run action is visually prominent and belongs to the plan beside it. `PlanRunControl` renders ready and continuation actions, a configuration-check action, or a completed/busy status. Completed state never resembles a disabled play button. Ordinary navigation and edit actions stay neutral. Destructive actions use the destructive role and remain separated from constructive actions. Icon-only buttons require a help label and accessibility label.

### Navigation and data display

The macOS sidebar is the persistent navigation model. Panels organize dashboards and editors; activity records use structured rows and expandable details. The sidebar footer shows global idle/running state and retains progress, stop and activity navigation during a run; it does not duplicate the plan picker or start action. Overview cards own their next scheduled time, compact expandable execution scope, readiness issues and plan action. Dense values use aligned digits, not oversized KPI decoration.

Activity places its record toolbar after the current-work panel and pins it when scrolling through records. The history heading and native three-part run selector (全部 / 提醒 / 失败) form the leading group; `ActivitySearchField` and the neutral icon-only actions menu form the trailing group. Narrow layouts move search and actions onto a second row. Toolbar content and date-grouped record panels share `PageLayout.inset`; a stable caption row explains the displayed scope and offers filter reset. The semantic window background keeps pinned content readable in either appearance without introducing another panel.

History uses aligned time columns, quiet dividers and two-line summaries inside one panel per day. A single run expands into account outcomes with drops and short explanations directly visible, followed by notices and an optional complete timeline; rows never expand automatically when new records arrive. Current recovery is a directly visible queue grouped by plan above the live run or daily state. Warning color is reserved for actionable state and recorded warnings, rather than repeated decorative badges. Search and level selection retain the whole matching run and never filter the live feed.

Content disclosures use `FullWidthDisclosureStyle`: the whole title row is a native button, at least 36 points tall, with explicit expanded state and keyboard focus. Only long diagnostics and optional historical detail start collapsed; actionable recovery and pending work stay visible. Sidebar hierarchy retains the native outline behavior.

### Forms and overlays

Data entry uses native controls and keeps validation near the affected setting. Short finite-choice pickers and numeric steppers use their native intrinsic width with `fixedSize(horizontal: true, vertical: false)` so labels, values and actions remain together. Text entry, segmented controls and sliders retain the space appropriate to their content. `DelimitedListField` retains raw editing text until focus leaves or the user submits; switching stage input modes preserves the chosen target. A controlling strategy choice precedes its conditional fields. Confirmation dialogs are reserved for destructive or consequential actions. Banners summarize save and run results in a bounded overlay; details remain in readiness or activity views. Save failures also persist in a bottom inset with a retry action until saving succeeds. Settings explains automatic saving without duplicating a manual save button. Banner and editable-name transitions respect Reduce Motion. Shared behavior and native-control ownership are documented in [UX-CONTRACT.md](UX-CONTRACT.md).

Task cards follow the plan’s step order. A configured schedule starts as a full-row expandable summary; new/disabled schedules and errors expose their controls. Task cards share `PlanParameterModeRow` and `PlanRecommendedParameters`; the parameter mode applies to the whole task. The fight card groups weekly annihilation, its weekday and regular stage settings in the left “作战安排” column, beside “用药与次数” on the right. Weekly annihilation uses `SettingsToggleRow` and a native weekday `Picker`, and remains available in both parameter modes. Explanations stay with their owning controls; combined account status and recovery follow below across the card. Execution policy likewise groups preparation and failure handling side by side. These sections stack at narrow widths; account status wraps rather than clipping long labels. `FightRecoveryActions` owns explicit weekly-confirmation, retry, and daily manual-handling actions in plan settings and the activity recovery queue. Confirmation and manual handling save records without launching a game; manual handling preserves the unconfirmed evidence and never counts as automatic success. Actions remain visible while busy, with an inline explanation. Activity places actionable current state before immutable historical runs; historical rows contain no live recovery or resume actions, and status counts wrap at narrow widths.

`PendingWorkList` shares the account, task or phase, and known reason presentation across Overview and Activity. It directly groups remaining work by account with wrapping rows and task symbols. Unstarted daily work stays in a compact state summary rather than enumerating future tasks. Run labels remain stable across task types; exact continuation scope comes from the core state model beside the action.

### Update behavior

`UpdateProgressRow` owns pending update feedback in Settings: named stage, elapsed time, the shared limit from `UpdatePolicy`, and a consistently labeled “取消更新” action aligned to the top of the row. Known transfer sizes add a native linear progress bar, received/total bytes and a percentage; unknown totals never produce an estimated percentage. Download completion yields to extraction, synchronization and validation feedback before the update is ready. Automatic and manual work use the same controls. Cancellation remains busy until cleanup finishes; old progress cannot survive cancellation, retry or a later attempt. Transfer samples stay transient and do not flood activity history. Errors remain beside the owning update action and in MAA activity history. `AppModel.startMAAUpdate` owns both automatic and manual MAA task lifecycle. `WorkflowRunner` owns staged validation and activation; the UI never infers compatibility.

“更新 MAA” includes the engine and recognition data; “仅更新识别数据” synchronizes separately published data without replacing the engine. Beta remains an explicit native confirmation. SwiftUI/macOS own focus, menus, semantic colors and scrolling; these native variants also apply to update controls.

Release information remains visible independently of operation state. Settings shows the installed and target versions with a short list of changes; `UpdateDetailsView` is the shared native sheet for full release notes and MAA installation comparisons. Settings uses one release-notes entry with an unread marker; when an update exists, its menu distinguishes the target and installed versions. About retains a permanent current-version entry. Headings, lists and source links preserve the upstream document structure; technical validation output stays in disclosure details. Offline or missing notes never replace known version information or change update eligibility. MAA history distinguishes the installed snapshot from a successfully activated snapshot and labels upstream GUI-specific content.

### Iconography

Use SF Symbols. Filled task symbols are acceptable inside the 2rem task container; ordinary action symbols follow the native rendering mode. Symbols support text rather than replace it for consequential actions.

Brand artwork is limited to project identity: `Assets/AutoMAA-logo.png` uses a tilted frame on transparency for README, documentation, sidebar and About. `Assets/AutoMAA-icon.png` uses a circular frame on a gradient rounded tile exclusively for the macOS application icon, generated as `Assets/AutoMAA.icns`. Web variants derive from the transparent logo. Preserve the character and framing across sizes; do not add artwork to operational controls.

### Motion

Motion communicates focus or state transitions and stays short, typically around 140ms for local feedback. Animations must be interruptible and respect Reduce Motion. Avoid continuous decorative animation.

### Content and data visualization

Product voice is direct, specific, and actionable. State copy says what happened and what the user can do next. Times use the user's locale and 24-hour scheduling presentation already established by the app. Counts and percentages use monospaced digits when they update in place. There is no chart palette until a data visualization is introduced with an accessible textual alternative.

## Do's and Don'ts

- **Do:** Keep safety checks, remembered state, and the next recovery action visible beside the setting they affect.
- **Do:** Reuse native controls, semantic colors, `Panel`, and established spacing before introducing a new component.
- **Don't:** Add game-themed decoration, gradients, or animated chrome to routine configuration surfaces.
- **Don't:** hide errors behind color-only state, transient hover, or layout-shifting banners.
