# Hand-drawn mascot assets

The app uses the original hand-drawn chick PNG directly. No 3D model is loaded,
rendered, or shipped in the iOS target.

Run the following command to create the two iOS-ready assets:

```bash
python3 Tools/Mascot/prepare_mascot.py compose \
  /absolute/path/to/ひよこ.png \
  Tools/Mascot/output/illustration
```

The generated files are:

- `ChickMascot.png`: transparent 1024 × 1024 image for in-app prompts
- `AppIcon.png`: opaque 1024 × 1024 icon with the app's starry background

The generator removes only pale fringe pixels connected to the transparent
outer background. This prevents a white jagged halo on dark UI while preserving
the white eggshell and the original watercolor artwork inside its brown outline.

Copy them to:

- `Sleeper/Assets.xcassets/ChickMascot.imageset/ChickMascot.png`
- `Sleeper/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
