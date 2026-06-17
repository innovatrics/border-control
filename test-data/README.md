# test-data/

Drop test video files here. VPP camera services mount this directory at `/tmp/test-data` and
loop the videos as synthetic camera streams.

The seed database (`db/smartface-seed.dump`) comes pre-configured with two cameras that
reference files in this folder:

| Camera | File |
|--------|------|
| test2 | `vlc-record-2026-05-29-11h05m17s-rtsp___192.168.8.3_554_axis-media_media.amp-.mp4` |
| test3 | `vlc-record-2026-05-29-landscape-4x3-up15.mp4` |

A shorter `street.mp4` is also useful for quick smoke-tests.

Video files are gitignored (large binaries). Get them from the shared Drive folder or from
a colleague's copy of the `corridor-foundations-stack-*.zip`.
