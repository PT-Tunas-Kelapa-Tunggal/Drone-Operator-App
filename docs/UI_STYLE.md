# macOS typography and controls

Updated 14 October 2026.

The Mac app uses semantic system fonts: title2 for page titles, headline for sections, body for controls, callout for supporting information, and title3 with monospaced digits for summary counts. The leaf mark is 20 points in a 28-point frame, with an 18-point wordmark. These brand dimensions are project choices, not sizes mandated by Apple.

Regular native control sizes are the default. Acquisition start and WebODM export use large prominent buttons. Toolbar actions use the native glass button style on macOS 26 and later; prominent actions use glassProminent. Earlier versions retain bordered styles. Glass is applied to interactive controls rather than every data surface. Accent colors adapt to light and dark appearance; selected navigation retains a dark green background for white text.

Cancel and mission creation sheets use standard keyboard shortcuts. Starting image acquisition does not receive a default Return shortcut.

References:
- [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple HIG: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)

Validation: ControlDroneMapping Debug build succeeded. Light and dark dashboard appearance were inspected in the running demo, including navigation, summary cards, toolbar controls, and settings. No clipping was observed at the inspected window size. This is not a certification of every accessibility configuration or window size. Capture and transfer behavior were not changed by this styling update.
