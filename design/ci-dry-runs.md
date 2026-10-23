# CI dry runs

`gh workflow run release.yml --ref main` builds the app on GitHub's `macos-26` runner (Xcode 26.6, macOS 26 SDK), signs and notarizes it when the repo's secrets exist (ad-hoc otherwise), packages `Stickermine.dmg` and keeps it as the `Stickermine-dry-run` artifact for 7 days. It is the only check against CI's project format, SDK, Swift and actool, so it runs as soon as the scaffold builds and again at the end of every milestone (spec section 17). One row per run, newest last.

| Date | Point | Commit | Run | Conclusion | Notes |
|---|---|---|---|---|---|
| 2026-10-23 | M1 scaffold (Task 5) | cbbf116 | https://github.com/grokcodile/stickermine/actions/runs/39964973942 | success | Ran on branch v1 (release.yml added to main alone so it can be dispatched); ad-hoc, no secrets yet |
| 2026-10-23 | M1 end (Task 12) | ab10bb9 | https://github.com/grokcodile/stickermine/actions/runs/39965873473 | success | branch v1; CI app minos 26.0, sdk 26.5 |
| 2026-10-23 | M2 end (Task 14) | 1b06013 | https://github.com/grokcodile/stickermine/actions/runs/39969991186 | success | branch v1 |
| 2026-10-23 | M3 end (Task 10) | 6d96c0b | https://github.com/grokcodile/stickermine/actions/runs/40037053453 | success | branch v1 |
| 2026-10-23 | M4 end (Task 19) | 0a53a80 | https://github.com/grokcodile/stickermine/actions/runs/40041387273 | success | branch v1 |
