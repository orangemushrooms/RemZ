# Alpine horizon

`alps_field_4k.hdr` is **Alps Field**, photographed by **Andreas Mischok**, distributed by Poly Haven under **CC0**.

- Asset: https://polyhaven.com/a/alps_field
- License: https://polyhaven.com/license
- Original download: https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/alps_field_4k.hdr
- Source location from the publisher's metadata: 46.609194, 9.429675 (Switzerland).
- SHA-256: `53a70291504177b47faf8a4dc598876e47740953d2cbc9af000d3a17095b9d42`

The original HDR file is unmodified. `shaders/alpine_sky.gdshader` places it at the distant horizon, compresses its apparent elevation, and blends atmospheric haze in the existing sky pass. It supplies an artistic Swiss Alpine backdrop, not a geographically surveyed view from Remetschwil. There are no mountain meshes, colliders, shadow casters, particles, or extra viewports.

The time-of-day shader keeps the horizon orientation fixed, replaces the photographed upper sky/sun with a moving sun, moon and sparse procedural stars, and fades the mountains into night haze. The source image remains unmodified. Reflection filtering uses a 128-pixel incremental cubemap, refreshed every 30 game seconds (three real seconds at 10×); it does not depend on shader `TIME` or camera position.

The optional faster continuous-day mode limits reflection updates to at most once per real second.

Godot references: [Sky](https://docs.godotengine.org/en/stable/classes/class_sky.html), [Sky shader update conditions](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html), [Environment](https://docs.godotengine.org/en/stable/classes/class_environment.html).
