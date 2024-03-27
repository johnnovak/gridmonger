## Making edits to the icon font

1. Unpack [GridmongerIcons-v1.0.zip](GridmongerIcons-v1.0.zip).
1. Open the [IconMoon App](https://icomoon.io/) in a browser.
1. Go to [Manage Projects](https://icomoon.io/app/#/projects), click on
   **Import Project**, then load `selection.json` from the unpacked archive.
1. Click **Load** and make your edits.
1. When finished updating the font, go to **Generate Font** and click
   **Download**. This will download a file called `GridmongerIcons-v1.0.zip`.
1. Update the ZIP in this folder and
   [Data/GridmongerIcons.ttf](../../Data/GridmongerIcons.ttf) with the TTF
   from the archive and commit the changes.

### Notes

- The IcoMoon App can import and export icons as SVG files.
- Use the pencil tool from the top toolbar in the **Selection** screen to edit
  the icons or to export them as SVG files. This is super handy for making
  quick adjustments to the icons' scaling and alignment on a pixel grid.
- Make sure to update [src/icons.nim](../../src/icons.nim) if you've added or
  removed icons.
