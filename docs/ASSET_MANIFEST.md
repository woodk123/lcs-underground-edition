# Generated art manifest

Generated on 13 October 2026 for Liberal Crime Squad: New Age using the built-in ChatGPT image generation tool (`image_gen.imagegen`). No CLI or API fallback was used. The generated originals remain under the Codex generated-images folder; the production copies are saved project assets, consumed from `upstream/assets/modern/`.

## Shared art direction

Restrained editorial screenprint / graphic novel illustration. Deep ink and navy shadows, warm off-white paper tones, muted teal, vermilion accents and amber practical lights. Fictional American city architecture and lived-in spaces. Crisp contours, subtle paper texture and consistent blue-hour lighting. No readable text, logos or interface are embedded in the artwork.

## Assets

| Asset | Intended use | Size | Bytes | SHA-256 |
| --- | --- | --- | --- | --- |
| `assets/art/city_panorama.png` | Title hero, city overview backdrop | 1536 × 1024 | 3,242,469 | `45C13FE656E6073FA3D22303FCBFE89CFBB6E7FCB9025C0966CC6FB3A6062A4C` |
| `assets/art/safehouse.png` | Safehouse/home base backdrop | 1536 × 1024 | 3,056,330 | `FBDF7C6C3E751168FF9B8414F3C0707F0E6CCD4FCC9A4A803BF893D60EEC4040` |

Both are opaque PNG images. The Flutter title and headquarters use copies at `upstream/assets/modern/city_panorama.png` and `safehouse.png`, with responsive cropping and dark scrims behind live text. The original generated copies above are preserved.

The simple app mark is a project-authored vector at `upstream/assets/modern/app_mark.svg`, matching the vermilion and paper UI colors. `scripts/export_app_mark.py` exports new native ICO and web PNG assets from that geometry; original upstream icons remain preserved. This vector icon is separate from the image-generated environmental illustrations.

## Provenance and review

- `city_panorama.png` source: `C:\Users\sheer\.codex\generated_images\01a136ac-648f-7f30-bb82-ef124ba0e6e6\exec-bf769349-bf13-4493-8181-58e5db48957c.png`.
- `safehouse.png` source: `C:\Users\sheer\.codex\generated_images\01a136ac-648f-7f30-bb82-ef124ba0e6e6\exec-2050c4da-1f99-4fc9-9cdc-05d6faaeaa92.png`.
- Safehouse generation used the city panorama as its sole style reference.
- Visually inspected both outputs: city includes a civic district, apartment streets, industrial rooftops and distant skyline; safehouse includes a meeting table, blank-paper corkboard, desk, shelves and dusk city windows.
- Reviewed for unwanted text, logos, UI, weapons and malformed major architectural/furniture forms; none observed.
- Width, height, byte size and SHA-256 were verified from the saved production copies.
- No external stock images, proprietary logos or third-party artwork were used in these generations.

## Exact generation prompts

### City panorama

```text
Use case: stylized-concept
Asset type: production game city overview and title hero, landscape 1536 x 1024 composition
Primary request: a polished wide panorama of a fictional American city at dusk for a sophisticated political strategy game.
Scene/backdrop: layered American city streets and neighbourhoods seen from an elevated viewpoint, with a recognizable civic courthouse and city hall, brick apartment blocks, an understated press office, industrial rooftops, tree-lined streets and a distant downtown skyline. Believable city geography with streets connecting districts, architecture conveying institutions and everyday life.
Style/medium: restrained graphic novel and editorial screenprint illustration, crisp confident ink outlines, layered flat graphic shapes with subtle paper grain, sophisticated architectural detail, clean silhouettes; premium art direction suitable for a modern PC strategy game.
Composition/framing: panoramic landscape, strong readable architecture across the scene with a calm upper sky and clear hierarchy; distant skyline, middle-ground civic district and close foreground rooftops; the scene should remain legible behind small interface markers. Do not create an interface.
Lighting/mood: blue-hour dusk, warm windows and street lamps, grounded and quietly tense but inviting, subtle atmospheric depth.
Color palette: deep ink and navy, warm off-white, muted teal, restrained vermilion highlights, a few warm amber windows. Strictly cohesive limited palette.
Constraints: no readable text, no lettering, no slogans, no logos, no symbols on banners, no UI, no labels, no watermark, no photorealism, no cartoon characters, no weapons. Entire image is finished art.
```

### Safehouse

```text
Use case: stylized-concept
Asset type: production strategy game safehouse interior illustration, landscape 1536 x 1024 composition
Input images: Image 1 is the sole style reference: match its restrained ink-lined graphic novel rendering, fine architectural details, navy dusk shadows, muted teal, warm paper tones, amber lighting and restrained vermilion accents. Create a different original interior scene using this exact visual language.
Primary request: the quiet organising room of a modest safehouse in a fictional American city, a believable lived-in home base for a political strategy game.
Scene/backdrop: a renovated brick apartment room with wood floor, large windows overlooking city rooftops at dusk, a sturdy central meeting table with mismatched chairs, a working desk and warm lamp, a corkboard on the wall with pinned blank papers and simple unlabelled diagrams, a shelf of files, a radio, an old sofa, a few stacked cartons and a potted plant. Calm, competent and resourceful rather than luxurious or chaotic.
Style/medium: editorial screenprint and restrained graphic novel illustration, fine confident ink contours and layered flat shapes, subtle paper texture, sophisticated clean detail and deep readable shadows.
Composition/framing: wide three-quarter view into the room at human eye level, table and desk provide the main shapes, corkboard and window in the middle ground; clearly readable and spacious enough to use as background artwork in a PC game.
Lighting/mood: blue-hour light from the window with warm amber lamplight and a cozy pool of light over the table, hopeful concentration and quiet determination.
Color palette: deep ink/navy, warm off-white, muted teal, restrained vermilion accents, amber light. Match Image 1.
Constraints: no readable text, no letters or numbers anywhere, no logos, no slogans, no flags, no UI, no watermark, no people, no weapons. Corkboard notes and book spines must contain no writing.
```

