# Offscreen window discovery in the existing macOS driver

MacosDriver.windows(onScreenOnly: false) lists all normal-layer windows for the
requested process, including other Spaces and hidden helper surfaces. Its native
symbol is additive; the original on-screen ABI/default remain. Custom bridges can
implement AllWindowListingBridge, or refuse that option without a native call.
MacosWindow.onScreen is nullable and toJson preserves absent OS metadata.

The consuming Flutter runner now calls this driver directly for discovery and
windowScreenshot for capture. Its temporary Swift discovery script/subprocess is
removed. Host window ID still comes from the explicit read-only native host;
PID membership is corroborated, wrong-owner capture refuses, and no size/title
ranking substitutes for identity. Unbound ambiguity still refuses.

48 package unit contracts pass. The opt-in native hook test builds/loads the
real old/new window APIs and checks native cache reuse and source invalidation.
The Oka native job passes text/keyboard/button/stale effects, empty error buffer,
inspected graph PNG and owned teardown. Foreground PID unchanged339 samples,
maximum gap30998us, activation trace empty. Window-content pixels are not
compositor timing or physical keyboard-event evidence.

Manifest freezes named sources across unit verification and byte-hashes copied
runtime receipts. Source snapshots are text, not another package. The runtime
list omits visibility for these other-Space windows; no false values are invented.
No new automation stack, hosted release, compiler-closure or adoption claim.
