# Roadmap & Future Implementations

This document serves as a living roadmap for the OrthoQuant MD application, tracking completed milestones and planned features based on clinical feedback.

## ✅ Completed Milestones (v0.6.1)

### Desktop & iPad Integration
- [x] **Drag & Drop Import:** Support for importing images by dragging files directly into the app window or onto the macOS application icon.
- [x] **Native File Associations:** Registered as an image viewer on macOS, allowing "Open With" and Dock-drop functionality.
- [x] **HEIC Support:** Added compatibility for High Efficiency Image Format (Apple Photos) for seamless clinical image imports.

### User Experience (UX)
- [x] **Smart Zoom v2.0:** Highly precise (2.2x) magnification triggered with a 1.2s hold, resolving previous magnifier impracticality.
- [x] **Template Categorization:** Organized advanced templates into a horizontal scrollable menu for easier navigation.
- [x] **Onboarding Tutorial:** Integrated step-by-step guidance for first-time users using `TutorialCoachMark`.
- [x] **Responsive UI:** Fixed layout regressions on iPads and smaller devices like iPhone XR.

### History & Organization
- [x] **History Folder Structure:** (PRO) Allows users to organize measurement records into groups/folders with drag-and-drop support.
- [x] **Group Management:** UI for creating, renaming, and deleting folders within the History screen.

### Business & Compliance
- [x] **Subscription Model (PRO):** Full integration with RevenueCat for Apple/Android subscriptions.
- [x] **Privacy Compliance:** Dedicated Privacy Policy documentation clarifying local clinical data storage.

---

## 🚀 Planned Features (Short-Term)

### Reporting & Export
- [ ] **Specific Measurement Names in PDF:** Update results table to use template-specific names (e.g., "HVA", "Q-Angle") instead of generic types ("Angle", "Distance").
- [ ] **Batch Export:** Select multiple records in History and export them as a single PDF or zip archive.
### Calculations & Decision Support
- [ ] **Clinical Scoring Modules:** Dedicated section for physician-reported outcome measures (e.g., Harris Hip Score, AOFAS, Constant-Murley).
- [ ] **Guideline Algorithms:** Interactive clinical pathways based on orthopaedic guidelines (e.g., treatment algorithms for classification-based decisions).
- [ ] **Pre-Op Risk Assessments:** Calculators for surgical risk and success probability based on patient metrics.

### UX Improvements
- [ ] **User Feedback Mechanism:** Internal form to send bug reports or feature requests directly to the dev team.
- [ ] **Template Visual Guides:** Side-panel diagrams showing the required anatomy for the current measurement step.
- [ ] **Re-implement Undo Button:** Feature was removed in v0.6.2 for UI simplification; needs to be re-introduced with a cleaner UI.

### Localization & Theme
- [ ] **Full Multi-language Support:** Complete Turkish/English translations for all instructional text.
- [ ] **Design System (Light/Dark):** Standardize color tokens to support system-wide theme toggling.

---

## 🔭 Future Vision (Long-Term)

### Advanced Analysis
- [ ] **AI-Assisted Point Detection:** Use computer vision to suggest initial point locations for standard measurements (e.g., femoral head center).
- [ ] **DICOM Support:** Native support for viewing and measuring directly on DICOM files.
- [ ] **Trend Analysis:** Graphs showing progress over time for specific patient records (e.g., post-op angle changes).

### Infrastructure
- [ ] **Secure Cloud Sync:** End-to-end encrypted backup of records (optional for PRO users).
- [ ] **Enterprise/Hospital Integration:** Support for HL7 or internal clinic servers.
