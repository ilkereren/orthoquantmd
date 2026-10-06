# Template Authoring Guide

This guide documents the template rules currently implied by the OrthoQuant MD
codebase. It is descriptive, not a redesign proposal: the goal is to make the
existing conventions explicit before adding or changing templates.

## Source Of Truth

Current template behavior is distributed across these files:

- `lib/templates/base/measurement_template_base.dart`: modular template API.
- `lib/models/template_model.dart`: shared template data models and legacy
  `appTemplates`.
- `lib/templates/template_registry.dart`: modular template registration.
- `lib/controllers/template_controller.dart`: active template state, restore,
  landmark-to-measurement mapping, and calculation measurement sync.
- `lib/screens/measurement_screen.dart`: user interaction flow, landmark
  auto-advance, result display, export table formatting, and remaining UI state.
- `lib/templates/**`: concrete examples of painting and calculation behavior.

## Two Template Systems Exist

There are currently two parallel systems:

1. Legacy `MeasurementTemplate` objects in `lib/models/template_model.dart`.
2. Modular `MeasurementTemplateBase` classes in `lib/templates/**`.

The active app still uses both:

- Menus and saved template restore use legacy `appTemplates`.
- Modular calculation/result rendering is resolved with
  `TemplateRegistry.getById(template.id)`.

Rule: a new modular template should use the same `id` as its legacy
`MeasurementTemplate` entry if both systems must coexist.

## Required Modular Template Contract

Every modular template extends `MeasurementTemplateBase` and must implement:

- `id`: stable unique id, typically snake_case.
- `title`: user-facing name shown in template UI and result box.
- `viewInfo`: radiographic view or acquisition context.
- `category`: one of `JointCategory`.
- `icon`: menu icon.
- `infoDescription`: detailed markdown-compatible clinical explanation.
- `landmarks`: ordered list of user-placed points.
- `calculate(points, imageRect, {pixelsPerMm})`: returns result strings.
- `paint(canvas, points, scale, paint, imageRect)`: draws overlay graphics.

## Landmark Rules

- Landmarks are `TemplateLandmark(id, label, instruction)`.
- `id` is machine-facing and should be stable snake_case.
- `label` is user-facing and is copied onto the generated point measurement.
- `instruction` is the step prompt shown while placing landmarks.
- Landmark order is the input sequence. `points[i]` corresponds to
  `landmarks[i]`.
- Current template flow creates landmarks as `MeasurementType.point`.
- The screen auto-advances after each completed point landmark.
- `areaPolygon` is an exception: it does not auto-advance; the user finishes it
  manually.

## Coordinate Rules

- User points are stored normalized, usually in the range `0..1` relative to the
  image.
- Template `calculate` and `paint` should convert points with:

```dart
denormalize(point.position, imageRect)
```

- `imageRect` is the rendered image rectangle on screen/canvas.
- If `imageRect.isEmpty`, existing templates return no results and draw nothing.
- Calculations that need image-space geometry usually denormalize all points
  before using `GeometryUtils`.

## Calculation Rules

- `calculate` returns `List<String>`.
- Default result parsing expects strings shaped like:

```text
Label: Value
```

- Units are included in the value string when relevant:

```text
LCEA: 32.4°
Ulnar Variance: -1.5 mm
Acromial Index: 0.72
```

- If required points are missing, return `[]`.
- If a geometric helper fails, return `[]` or skip that result rather than
  throwing.
- Use `pixelsPerMm` only when it is non-null and greater than zero.
- If calibrated distance is unavailable, current templates either:
  - report pixel units, or
  - omit distance conversion while still reporting angular/index results.

## Paint Rules

Existing templates follow these visual conventions:

- Convert normalized points to screen coordinates before drawing.
- Draw placed landmark points as small filled circles, commonly
  `3.0 / scale` or `4.0 / scale`.
- Divide stroke widths by `scale` so overlays remain visually stable while
  zooming.
- Use `paintExtendedLine` for axis/reference lines that should extend across
  the image.
- Use `paintDashedLine` for helper/reference constructions.
- Common colors:
  - Main measured lines: cyan / cyanAccent.
  - Secondary or calculated lines: yellow / yellowAccent.
  - Mechanical/reference lines: greenAccent or white with alpha.
  - Landmark points: blue, orange, or the inherited paint color.
- Never assume all landmarks exist inside `paint`; guard by `points.length`.

## Result Box Rules

The default `buildResultBox` in `MeasurementTemplateBase` parses each result by
splitting on `": "`.

- `"Label: Value"` becomes a row with label and value.
- A string without `": "` becomes label-only with an empty value.
- Templates may override `buildResultBox` for custom layout, but most should use
  the default.

## Legacy Calculation Measurement Rules

Legacy `TemplateCalculation` links landmarks into generated
`MeasurementModel`s:

- `id`: stable calculation id.
- `label`: result label.
- `type`: `MeasurementType`.
- `landmarkIds`: landmark ids mapped into measurement point order.
- `forceAcute`: used for acute-angle behavior.
- `isAuxiliary`: helper calculation; hidden from result list in the screen.

`TemplateController.syncMeasurements()` creates or updates generated
measurements from mapped landmarks. Generated calculation measurements are:

- `isTemplateResult: true`
- `color: Colors.yellowAccent` by default
- `isLocked: false` currently, per existing behavior
- `isAuxiliary` copied from the calculation

Rule: if a template requires special point transformation, keep it centralized
in template sync logic or in the modular template calculation, not scattered in
the UI.

## Active Template Lifecycle

Current flow:

1. User selects a template from the menu.
2. If another template is active, the screen asks for replacement confirmation.
3. `TemplateController.activate` resets template state.
4. First landmark measurement is created.
5. Each tap adds a normalized point.
6. The screen auto-advances to the next landmark.
7. Intermediate calculation sync may run after each point.
8. After the last landmark, results are generated and the last point is
   deselected.
9. Deleting any measurement belonging to the template removes the entire active
   template measurement set.

## Restore Rules

Saved records store `templateId`.

Restore currently:

- Finds the legacy template by `templateId`.
- Sets active template state.
- Maps landmarks by matching `MeasurementType.point` and landmark `label`.
- Maps calculations first by `label`, then by unique matching type/auxiliary
  state.
- Contains special mapping for `glenoid_bone_loss` and `glenoid_version`.

Rule: landmark labels should remain stable enough for restore to work.

## Registration Rules

For a new modular template:

1. Create a class under the appropriate `lib/templates/<category>/` folder.
2. Extend `MeasurementTemplateBase`.
3. Add the import and instance to `TemplateRegistry._templates`.
4. If the legacy menu still needs it, add a matching `MeasurementTemplate` entry
   to `appTemplates` with the same `id`.
5. Add or reuse clinical copy in `TemplateDescriptions` if the template uses
   shared markdown descriptions.

## Clinical Text Rules

Current templates place detailed clinical descriptions either:

- inline in `infoDescription`, or
- in `TemplateDescriptions.infoDescriptions`.

The description should include:

- View/projection.
- Landmark definitions.
- Measurement definition.
- Normal/pathologic interpretation when appropriate.
- Notes/limitations if the measurement depends on projection quality.

## Safety Checklist Before Adding A Template

- All required getters are implemented.
- `id` matches legacy entry if using both systems.
- Landmark ids are stable and unique.
- Landmark order matches calculation index assumptions.
- `calculate` returns `[]` for insufficient points.
- `paint` guards every point access by length.
- All normalized points are denormalized before screen/image-space geometry.
- `pixelsPerMm` is checked before mm conversion.
- Result strings follow `"Label: Value"` unless a custom result box is used.
- Template is registered in `TemplateRegistry`.
- If legacy menu support is needed, matching `appTemplates` entry exists.
- `flutter analyze` and `flutter test` still pass at the project baseline.

