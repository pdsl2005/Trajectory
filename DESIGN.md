# DESIGN.md — Trajectory (SwiftUI / iOS)

## 1. Design Philosophy & Core Principles
Trajectory bridges short-term monthly budgeting with long-term life forecasting. Because financial data is inherently dense, the UI follows four foundational principles:

* **Progressive Disclosure:** Present high-level projections and budget summaries first. Use `DisclosureGroup` rows, sheets, and chart scrubbing to reveal granular line items, tax assumptions, or return-rate ranges without cluttering the base canvas.
* **Balanced Density:** Avoid cramped spreadsheet grids and overly airy consumer cards. Rely on SwiftUI's native `Form` and `List` insets paired with an 8pt spacing rhythm (`8`, `12`, `16`, `24`) so numbers scan effortlessly.
* **Tabular Precision:** Financial interfaces fail when numbers jitter or misalign. Apply `.monospacedDigit()` to every numeric `Text` view and right-align currency/percentage columns.
* **Calm Confidence:** Slate blue anchors the interface with stability and trust. Reserve high-chroma colors strictly for interactive controls and semantic financial deltas.

---

## 2. Information Architecture & Navigation
Use a native `TabView` (maximum 4 destinations) with a `NavigationStack` inside each tab:

1. **Trajectory (Overview):** Net worth projection chart (`Swift Charts`), scenario switcher `Picker` (`.segmented` or `.menu`), and key milestone summary cards.
2. **Budget:** Monthly cash flow, category allocations, and recurring income/expense tracking.
3. **Scenarios:** Side-by-side life event modeling (job changes, major purchases, retirement age) and investment return-rate range testing.
4. **Accounts & Data:** Assets, liabilities, household member toggles, and local-first export/backup (`ShareLink` / `fileExporter`).

---

## 3. Color System (Asset Catalog Tokens)
Define semantic color sets in `Assets.xcassets` supporting **Any Appearance (Light)** and **Dark** variants. All pairings must meet **WCAG AA** contrast minimums (4.5:1 body text, 3:1 UI components).

### Brand & Surfaces
| Asset Token | Light Mode | Dark Mode | SwiftUI Usage |
| :--- | :--- | :--- | :--- |
| `BrandPrimary` | `#3B5978` | `#688EB5` | `.tint(.brandPrimary)`, active chart curve, primary buttons |
| `BrandSubtle` | `#EEF3F8` | `#1E2936` | Active scenario pills, selected row highlights |
| `SurfaceCanvas` | `#F8F9FB` | `#0F1216` | `.scrollContentBackground(.hidden)` root background |
| `SurfaceElevated` | `#FFFFFF` | `#181D24` | Card containers, grouped list rows |
| `BorderHairline` | `#E2E7EE` | `#28303B` | `Divider()`, `1.stroke` card borders (`0.5pt`) |

### Typography Colors
Use native system hierarchical styles where possible so vibrancy and contrast adapt automatically:
* **Primary Figures & Headers:** `.primary` (`#111827` Light / `#F3F4F6` Dark)
* **Labels & Axis Ticks:** `.secondary` (`#4B5563` Light / `#9CA3AF` Dark)
* **Placeholders & Footnotes:** `.tertiary`

### Semantic & Financial Deltas
| Asset Token | Light Mode | Dark Mode | Usage |
| :--- | :--- | :--- | :--- |
| `DeltaPositive` | `#15803D` | `#4ADE80` | Net gains, under-budget variance, asset growth |
| `DeltaPositiveBg` | `#DCFCE7` | `#143322` | Capsule badge fill for positive deltas |
| `DeltaNegative` | `#B91C1C` | `#F87171` | Debt increase, over-budget variance, cash shortfall |
| `DeltaNegativeBg` | `#FEE2E2` | `#3B181A` | Capsule badge fill for negative deltas |

---

## 4. Typography & Dynamic Type
Use semantic `Font` styles rather than fixed point sizes so the app scales cleanly with iOS Dynamic Type:

* **Hero Projection Total:** `.largeTitle.bold().monospacedDigit()`
* **Section Headers:** `.title3.weight(.semibold)`
* **Card & Group Headers:** `.headline`
* **Body & Form Labels:** `.body`
* **Financial Table Figures:** `.body.weight(.medium).monospacedDigit()` (right-aligned)
* **Delta Badges & Captions:** `.caption.weight(.medium).monospacedDigit()`

---

## 5. Layout, Spacing & Geometry
* **Spacing Scale:** `8pt` (tight element gaps), `12pt` (between stacked cards), `16pt` (card internal padding and horizontal screen margins), `24pt` (major section breaks).
* **Corner Radii:** Always use `.continuous` corner style (`RoundedRectangle(cornerRadius: 12, style: .continuous)`):
    * Cards & Chart Containers: `12pt`
    * Buttons & Custom Inputs: `10pt`
    * Scenario Pills & Delta Badges: `Capsule()`
* **Interactive Targets:** Rely on native SwiftUI controls (`Button`, `Toggle`, `Picker`, `Stepper`) which enforce `44pt` minimum hit targets automatically.

---

## 6. Core Component Specifications (SwiftUI)

### A. Interactive Forecast Plots (`Swift Charts`)
Build all projections with Apple's `Charts` framework (`Chart { ... }`):
* **Marks & Hierarchy:**
    * *Baseline Scenario:* `LineMark` styled with `.foregroundStyle(.secondary)` and `.lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))`.
    * *Active Scenario:* `LineMark` styled with `.foregroundStyle(Color.brandPrimary)` and `.lineStyle(StrokeStyle(lineWidth: 2.5))`.
    * *Investment Return Range:* `AreaMark(x:yStart:yEnd:)` rendered behind the median curve using `Color.brandPrimary.opacity(0.15)`.
* **Scrubbing Interaction:** Attach `.chartXSelection(value: $selectedDate)` to track user drag gestures. Render a vertical `RuleMark` at `selectedDate` and bind the scrubbed value directly to the card's top hero `Text` readout so the user's finger never obscures the active number.
* **Axes:** Limit `AxisMarks` to 3–4 clean horizontal gridlines with `.value.formatted(.currency(code: "USD").notation(.compactName))` (`$500K`).

### B. Financial Data Tables & Breakdowns
* **Alignment:** Use `HStack` rows with `Text(label)` on the leading edge, `Spacer()`, and `Text(amount).monospacedDigit()` on the trailing edge. For multi-column comparisons (e.g., *Current* vs. *Scenario*), use SwiftUI's `Grid` with `GridRow` and `.gridColumnAlignment(.trailing)` on numeric columns.
* **Expandable Categories:** Use `DisclosureGroup` inside `.listStyle(.insetGrouped)` to let users expand parent categories (e.g., *Housing*, *Investments*) into indented child items.

### C. Budgeting Formats
* **Category Progress:** Use native `ProgressView(value: spent, total: budgeted)` styled with `.tint(spent > budgeted ? .deltaNegative : .brandPrimary)`.
* **Monthly Cash Flow Header:** Display a prominent *Remaining / Surplus* readout paired with a multi-segment horizontal capsule bar showing *Needs*, *Wants*, and *Savings/Debt* proportions.

### D. Scenario & Household Modeling Forms
* **Structure:** Use native SwiftUI `Form` with `Section` headers for creating/editing life events (e.g., *Job Change*, *Retirement Age*, *Major Expense*).
* **Numeric Inputs:** Use `TextField("Amount", value: $amount, format: .currency(code: "USD"))` with `.keyboardType(.decimalPad)` and a `ToolbarItemGroup(placement: .keyboard)` containing quick-adjust buttons (`-$100`, `+$100`) and a `Done` button via `@FocusState`.
* **Live Impact Footer:** Attach a `.safeAreaInset(edge: .bottom)` bar inside scenario editor sheets showing the real-time 10-year net worth delta badge as sliders or steppers change.

---

## 7. Motion & Haptics
* **Transitions:** Use `.animation(.snappy(duration: 0.25), value: activeScenario)` when switching scenarios or toggling household members. Avoid high-bounce springs on financial figures.
* **Numeric Counter Transitions:** Apply `.contentTransition(.numericText())` to hero currency readouts when toggling between scenarios or scrubbing dates.
* **Haptics:** Use SwiftUI's native `.sensoryFeedback(.selection, trigger: selectedDate)` on chart scrubbing and steppers, and `.sensoryFeedback(.success, trigger: didSaveScenario)` on commits.