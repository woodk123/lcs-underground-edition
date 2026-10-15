# City sprites, portraits and animation

These original game assets were generated with ChatGPT's built-in `image_gen.imagegen` tool on 13 October 2026. They extend the existing dusk city art: ink/navy contours, warm stone and paper, weathered brick, muted teal, vermilion accents and amber light. No commercial game's artwork was copied into the runtime.

The selected PNGs are byte-for-byte copies of the generated outputs. There was **no image postprocessing**, resizing, background removal script, atlas repacking or manual cropping. The renderer crops source rectangles at runtime and preserves generated alpha. Read-only Pillow inspection measured dimensions, alpha and bounds; it did not rewrite images.

## Selected runtime assets

| Asset | Dimensions and format | Contents | SHA-256 |
| --- | --- | --- | --- |
| `upstream/assets/modern/building_sprites_v2.png` | 1254 × 1254, RGBA | 16 isolated isometric building types | `bae3af57cfe77627eefdbaff3a9c193a29154e5a5c976cd1f73fd398b0c47263` |
| `upstream/assets/modern/crew_portraits_v1.png` | 1254 × 1254, RGB | 16 distinct adult head-and-shoulders portraits | `25134e519a8151730ededaf2b94fed8f43543a81d917a04a5e74102e45cf6e07` |
| `upstream/assets/modern/pedestrian_walk_v2.png` | 1536 × 1024, RGBA | Eight sequential walk poses, 4 columns × 2 rows | `ed117eb4a247ef4848997971a326ee0541f2106b98560983c9b1378d8f1e5048` |

Workspace originals, prompts, rejected explorations and the complete machine-readable crop contracts are under [`assets/art-city-v2`](../assets/art-city-v2/). Only the three selected new sheets are installed in the runtime asset folder; discarded atlas/walk attempts remain outside it.

## Building atlas contract

The visual arrangement is four columns × four rows, but the generated gutters are not mathematically equal. **Use the explicit source rectangles in [`atlas_metadata.json`](../assets/art-city-v2/atlas_metadata.json), not equal-quarter cropping.** Each `source_rect` is `[x, y, width, height]` in PNG pixels and includes four pixels of padding around measured visible bounds. `foot_anchor_in_source_rect` gives the bottom-center footprint position. Preserve the source aspect ratio and place this anchor at the scene's building base.

Row-major types are apartment/safehouse, neighborhood shop, café, warehouse; factory, media office, courthouse, police station; hospital, university, bank, prison; office tower, suburban house, farm/ranch, city hall. These are illustration choices for the original game's locations, not a new location taxonomy or gameplay rules.

The v1 trial had boundary contacts and unsuitable equal-grid cropping. An imagegen edit retained the architectural designs while separating the silhouettes. The v2 result was visually inspected: all 16 types are recognizable, complete and separated. Alpha spans 0–255; gutters are genuinely transparent. The renderer's crop table accommodates the actual generated layout without modifying PNG pixels.

## Portrait atlas contract

Crop the 4 × 4 atlas in equal quarters: each source cell is 313.5 × 313.5 pixels. Fractional source rectangles are valid for the renderer. All faces use coherent paper backgrounds and framing, with no names, labels or UI embedded in the art. The crop order, visual descriptions and coordinates are in the metadata file.

Portraits are illustrative likenesses. Stable selection may use existing character identity/presentation data; it must not assign new simulation statistics or infer unrecorded biography from the artwork. Adult portraits must not be presented as a literal likeness of a child character.

## Walk animation contract

The selected sheet contains eight distinct contact, recoil, passing and raised-leg swing poses with alternating arm swing. It is an image-frame animation, not a translated static portrait. The first generated attempt repeated almost the same stride and was rejected.

Each cell is 384 × 512 pixels. Read frames 0–3 across the first row, then 4–7 across the second row; loop at approximately 8 frames per second. The generated frames have small alignment differences. Use their explicit foot anchors from the metadata and a common pixel scale, rather than stretching every silhouette independently. This keeps the street footprint stable while allowing the original pose/bob differences.

The sheet has 1,176,238 fully transparent pixels; alpha spans 0–254. Dark RGB values under alpha-zero pixels are preserved exactly as generated and are invisible when composited correctly. The scene should treat the civilian as ambient decoration: animating it does not advance campaign time or represent an order being carried out. Reduced-motion settings should freeze decorative animation.

## Exact prompts and generation provenance

All calls used built-in image generation, with `transparent_background: true` for buildings/walk and `false` for portraits. No API key or CLI fallback was used.

| Output | Exact prompt | Original generated file |
| --- | --- | --- |
| Building design trial | [`building_sprites_v1.prompt.txt`](../assets/art-city-v2/explorations/building_sprites_v1.prompt.txt) | `C:\Users\sheer\.codex\generated_images\01a1372c-83ad-75a2-849d-f3e0daa8356b\exec-7b4f8382-5c6a-4b3e-80d8-79d00f7eba07.png` |
| Selected building edit | [`building_sprites_v2.prompt.txt`](../assets/art-city-v2/building_sprites_v2.prompt.txt) | `C:\Users\sheer\.codex\generated_images\01a1372c-83ad-75a2-849d-f3e0daa8356b\exec-dd231bf0-634e-45d5-950a-6e21623cda0a.png` |
| Selected portraits | [`crew_portraits_v1.prompt.txt`](../assets/art-city-v2/crew_portraits_v1.prompt.txt) | `C:\Users\sheer\.codex\generated_images\01a1372c-83ad-75a2-849d-f3e0daa8356b\exec-d8e952ab-e564-4fa0-94d2-0d505f8f9bcd.png` |
| Rejected repeated-stride walk | [`pedestrian_walk_rejected_v1.prompt.txt`](../assets/art-city-v2/explorations/pedestrian_walk_rejected_v1.prompt.txt) | `C:\Users\sheer\.codex\generated_images\01a1372c-83ad-75a2-849d-f3e0daa8356b\exec-c771e185-7898-4238-b225-ad5302f74bd6.png` |
| Selected walk cycle | [`pedestrian_walk_v2.prompt.txt`](../assets/art-city-v2/pedestrian_walk_v2.prompt.txt) | `C:\Users\sheer\.codex\generated_images\01a1372c-83ad-75a2-849d-f3e0daa8356b\exec-c1334288-aec2-4c8e-95dc-c26583966c06.png` |

The building edit referenced the inspected v1 local PNG. All other calls generated new images from their saved prompts. The existing panorama was inspected for stylistic continuity before prompting; it was not an edit target.
