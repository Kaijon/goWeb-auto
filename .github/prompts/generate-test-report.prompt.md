---
description: Generates an interactive HTML test report with coverage metrics and test results visualization.
tools: [read-file]
---

# Task
Create a comprehensive HTML test report generator for the Embedded Camera Configuration Backend tests.

# Context Gathering
1. Read `cmd/server/main_test.go` to understand test structure and coverage areas.
2. Read `tests/integration_test.go` to understand integration test patterns.
3. Review test execution output (pass/fail counts, coverage percentages, execution times).
4. Understand the bitrate-policy constraints from `docs/specs/bitrate-policy.md`.

# Report Requirements

## 1. Report Structure
* **Header Section:** Project name, test date/time, summary metrics
* **Executive Summary:** 
  - Total tests run, passed, failed
  - Overall code coverage percentage
  - Test execution time
  - Key statistics
* **Coverage Report:** 
  - Package-level coverage breakdown
  - Line-by-line coverage visualization
  - Coverage trend indicators
* **Test Results:** 
  - Categorized test breakdown (unit, integration, benchmarks)
  - Individual test results with execution times
  - Failed test details and error messages
* **Performance Metrics:**
  - Benchmark results with operations/sec
  - Memory allocation statistics
  - Comparison against baselines
* **Hardware Constraint Validation Matrix:**
  - Visual table showing all tested resolution/bitrate combinations
  - Pass/fail indicators for each combination
  - Coverage heatmap

## 2. Interactive Features
* **Expandable/Collapsible Sections:** Click to expand test details
* **Filter Controls:** Filter by test type (passed/failed/skipped)
* **Search Functionality:** Search for specific test names or error messages
* **Progress Indicators:** Visual progress bars for coverage percentages
* **Color Coding:** Green (pass), Red (fail), Yellow (skipped), Blue (coverage)

## 3. Technical Implementation
* **HTML5 Semantic Structure:** Proper semantic tags and accessibility
* **Inline CSS Styling:** Self-contained file with no external dependencies
* **JavaScript Interactivity:** Vanilla JavaScript (no frameworks) for filtering/search
* **Responsive Design:** Mobile-friendly layout
* **Print-Friendly:** Optimized for PDF export

## 4. Data Section
* **Raw Test Data:** JSON-formatted test results embeded in HTML
* **Coverage Data:** By-file coverage metrics
* **Build Information:** Go version, test framework, timestamp
* **Environment Details:** OS, architecture, hardware info

# Output
- Single standalone HTML file: `test-report.html`
- Self-contained (no external CSS/JS dependencies)
- Can be opened directly in any web browser
- Suitable for CI/CD pipeline integration
- Can be committed to repository or generated as build artifact

# Implementation Notes
1. **Standalone:** All CSS and JavaScript inline - no external files required
2. **Accessibility:** WCAG 2.1 AA compliant with proper ARIA labels
3. **Performance:** Lazy-load heavy content with progressive enhancement
4. **Styling:** Professional, minimal design with good readability
5. **Data:** Parse Go test output format and convert to HTML representation
6. **Charts:** Use Canvas or SVG for coverage visualization
