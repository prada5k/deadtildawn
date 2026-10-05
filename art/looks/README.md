# Pictures for 3D parts

Drop source pictures here; Claude turns them into 3D models for the car.

| File | What | How it becomes 3D |
|---|---|---|
| `wing_gt.png` | the GT wing (body-colored pedestal wing) | built by script from the picture (`wing_gt` in build_dx.py); AI image-to-3D (Hyper3D Rodin) when its credits allow |
| `wheels/wheels_light.png` | the lightweight 15s: chrome Konig Countergram | measured off the photo, built by `art/blender/build_wheels.py` |
| `wheels/wheels_forged.png` | the forged 15s: white Buddy Club P1 | same |

For the AI route, the picture should be a **realistic product photo**:
3/4 view, plain white background, the whole part in frame, no text or
logos, no cartoon outline (flat cartoon shading makes the AI build flat,
blobby shapes). For wheels: **straight on**, face toward the camera, and
name the real wheel if it's one.
