# Notice

`JetNews/` is a **modified copy** of the JetNews sample from
[android/compose-samples](https://github.com/android/compose-samples), taken at commit
`0bbd72d69834ec86a9a72bd3513118755fb286c5` (2026-09-18). It is Copyright The Android Open Source
Project and licensed under the Apache License, Version 2.0, whose text is in [`LICENSE`](LICENSE),
copied from the root of that repository.

The fonts under `JetNews/app/src/main/res/font/` are licensed under the SIL Open Font License 1.1; see
[`JetNews/ASSETS_LICENSE`](JetNews/ASSETS_LICENSE), kept as upstream ships it.

## Changes from upstream

This repository's first commit is the upstream `JetNews/` directory unchanged. Every change since is a
commit in this repository's history. To the app itself there is one:

- `data/posts/impl/PostsData.kt`: the home feed's "recommended" and "history" sections repeat their
  posts ten times, each copy with its own id, so that the feed is several screens long.

The patches in `plants/` are further modifications, applied to a build only for the duration of one
capture and never committed to `JetNews/`.

Everything outside `JetNews/` (the harness, the plants, the runs) is new, under the same Apache-2.0
licence. The harness is adapted from superPlayer's `devicelab/`, also Apache-2.0.
