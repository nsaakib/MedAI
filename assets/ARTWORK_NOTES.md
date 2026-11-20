# Med.ai artwork

The built-in image-generation tool recreated the three existing small illustrations as transparent 1536×1024 production assets. The images preserve the original subjects and blue/cyan glass style; they are newly rendered recreations rather than exact restoration of missing source pixels. Each was visually inspected, and alpha and file decoding were checked.

Final project paths (relative to `mobile`):

- `assets/welcome_art.png`, `assets/2.0x/welcome_art.png`, `assets/3.0x/welcome_art.png`
- `assets/login_art.png`, `assets/2.0x/login_art.png`, `assets/3.0x/login_art.png`
- `assets/signup_art.png`, `assets/2.0x/signup_art.png`, `assets/3.0x/signup_art.png`

The 1×/2×/3× widths are 480/960/1440 pixels, all at a 3:2 aspect ratio. Flutter resolves the matching density variant. Image dimensions never determine screen layout; the containing layout sets proportional bounds and uses `BoxFit.contain`. Downsampled variants preserve generated alpha. Logos, loading graphics and background waves are native vector drawings.

## Prompt set used

Shared edit prompt:

> Edit target is the attached small Med.ai illustration. Recreate the same visual subject and composition with crisp premium blue glass 3D rendering at high resolution, landscape 1536x1024. Preserve the cyan/blue palette and main arrangement. This is a production mobile app asset, NOT a screenshot or UI mockup. Transparent background with genuinely transparent alpha, no navy rectangular backdrop, no text, no border, no watermark. Keep all objects inside the canvas with 10% transparent breathing room. Refined luminous edges, controlled soft cyan glow, not an excessive halo. Clean anti-aliased contours.

Subject appended for each asset:

- Welcome: A luminous medical plus symbol floating above the same blue open palm, surrounded by three small glass bubbles showing a heart pulse, a shield and a chart, with subtle orbital arcs. Keep the hand shape elegant and anatomically plausible.
- Login: A single blue translucent layered shield containing a white closed padlock, encircled by one thin cyan orbit and two tiny dots. Keep it a simple security illustration.
- Signup: Three overlapping upright translucent blue healthcare record cards with a white medical plus on the front, subtle short blank lines above the plus, thin cyan orbital arc and two dots. No letters or numbers.
