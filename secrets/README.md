# secrets/ — licensed material (do NOT commit / publish)

Everything in this folder is **Innovatrics-licensed** and stays internal. The `.gitignore` at the
stack root excludes this whole directory, so it never lands in version control. `run.sh` reads both
files from here.

| File | What | If missing |
|---|---|---|
| `iengine.lic` | IFace engine license. Mounted into **every** SmartFace container *and* CIGS. | SmartFace + CIGS refuse to start. Drop in a valid `iengine.lic` (1.4 KB). |
| `cigs.env` | Defines `IFACE_SPEED_MATCH_PHRASE` (CIGS speed-match license phrase). | CIGS exits on boot. Set the phrase in `cigs.env`, or `export IFACE_SPEED_MATCH_PHRASE=…` before `./run.sh`. |

Both ship pre-filled in this bundle so `./run.sh` works out of the box for an internal teammate.
**Before sharing this folder more widely, delete these two files** (or replace with your own) — the
recipient supplies their own license. `cigs.env.example` is the empty template to copy from.
