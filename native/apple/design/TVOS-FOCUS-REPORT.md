# tvOS Focus Report (OpenStream Apple TV)

**Date**: September 2, 2026

## Methodology
Driven via Siri Remote on the OpenStream Apple TV Simulator (tvOS 18) navigating through: Discover → Detail → Live → Settings.

## Findings

### 1. Discover Tab
- **Issue**: Focus is visually lost (invisible) when navigating between the top category chips and the hero card.
- **Cause**: Custom button wrappers are overriding tvOS's native focus scaling and parallax effects.
- **Screenshot**: ![Discover Focus Lost](discover-focus-lost.png)

### 2. Detail Page
- **Issue**: Focus gets trapped or defaults incorrectly upon presentation. The primary "Play" button doesn't receive default focus when the view appears.
- **Recommendation**: Attach `@FocusState` to auto-focus the primary Play button immediately upon entering the detail screen.
- **Screenshot**: ![Detail Focus Trapped](detail-focus-trapped.png)

### 3. Live Tab
- **Issue**: Navigating down the EPG timeline sometimes loses focus if a channel has no guide data, trapping the user in the channel list column.
- **Screenshot**: ![Live Tab Focus Trap](live-focus-trap.png)

### 4. Settings
- **Issue**: The "Add Network Share" modal has invisible focus on the text fields, making it impossible to know which field the Siri Remote is currently targeting. 
- **Screenshot**: ![Settings Invisible Focus](settings-invisible-focus.png)

*Done / hooks needed: None (Read-only report).*
