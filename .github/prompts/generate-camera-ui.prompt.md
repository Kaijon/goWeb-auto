---
description: Generates the Vue.js configuration interface for the camera.
tools: [read-file]
---

# Task
Create a Vue.js component for the Embedded Camera Configuration Web UI. 

# Context Gathering
1. Read `docs/specs/bitrate-policy.md` to get the strict hardware constraints AND the specific Web UI input requirements.
2. Review any existing global styles in the project if needed.

# Component Guidelines
1. **Follow the Spec:** Implement the inputs and reactive dynamic validation exactly as described in the `Web UI Requirements` section of the spec file.
2. **Submission State:** Include an "Apply" button.
    * The button must be disabled if an invalid combination is selected.
    * Show a loading state ("Waiting for camera...") while the apply function is processing.
3. **Error Handling:** Display a clear error message on the UI if the backend validation fails.

# Output
Provide the complete Vue.js Single File Component (`CameraConfig.vue`) using the Composition API (`<script setup>`).