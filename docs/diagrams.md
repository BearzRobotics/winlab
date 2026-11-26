# Lesson diagrams

WinLab draws lesson diagrams itself from a **small subset of SVG**. They scale with the window, use the app's fonts and follow the light or dark theme. (DVUI's own SVG converter has no `<text>` support, so labels would be lost.)

## Adding one

1. Put `name.svg` in a `diagrams/` folder next to the lesson's Markdown.
2. In the lesson, put the image **alone in its own paragraph**, and **directly after it** a `text` code block with the same picture in plain ASCII:

   ````markdown
   ![What the diagram shows, in a sentence](diagrams/name.svg)

   ```text
   +-------+      +-------+
   |  one  | ---> |  two  |
   +-------+      +-------+
   ```
   ````

3. Run `winlab check course`.

The lesson window shows the drawing, with **Copy as text** for the ASCII version. Plain-text view, copying the whole lesson and `winlab view` show the text. If a drawing cannot be loaded, the window shows the text version too. Only top-level images are drawn, not ones inside lists or tables. Screen readers have not been tested.

## The supported subset

| Element | Attributes |
|---|---|
| `svg` | `viewBox="0 0 W H"` (required), `xmlns`, `width`, `height`, `role`, `aria-label`, `font-family` |
| `rect` | `x`, `y`, `width`, `height`, `rx`, `class` |
| `line` | `x1`, `y1`, `x2`, `y2`, `class`, `marker-end` (any value draws an arrowhead) |
| `text` | `x`, `y` (the baseline), `font-size` (6 to 60), `text-anchor` (`start`, `middle`, `end`), `class` |

`style`, `defs`, `title` and `desc` are allowed and **ignored**: use them so the file also looks right in a web browser. Coordinates are plain numbers from 0 to 4000. A label is one line of text; only `&lt;` `&gt;` `&amp;` `&quot;` `&apos;` are recognised.

**Colours come from classes**, never from `fill` or `stroke` attributes:

| Class | Look |
|---|---|
| `zone-user`, `zone-kernel` | Tinted areas with a coloured edge |
| `hardware` | A grey fill |
| `accent` | The theme's highlight colour |
| `dim`, `bold`, `mono` | For labels |
| `box`, `wire`, `label` | The plain look (names for the browser style sheet) |

(`dashed` is accepted but not drawn differently yet.)

Anything else is an error. Lesson files are treated as untrusted: the reader never follows a link, runs a script or reads another file, and a lesson may only name a path inside its own folder.
