# secrets/ — licensed material (do NOT commit / publish)

Everything in this folder is **Innovatrics-licensed** and stays internal. The `.gitignore` at the repository root excludes `secrets/*.lic`; this README stays tracked.

One `iengine.lic`, tied to the hardware of the machine, is mounted into every service. Face Matcher needs its **iengine/IFace** block.

| File | What | If missing / incomplete |
|---|---|---|
| `iengine.lic` | Hardware-bound Innovatrics license for the machine. | The platform services refuse to start and log `No license file was found` or `License has different HWID than this machine`. |

`start.sh` symlinks this file to `platform/iengine.lic`, where the platform's own `run.sh` expects it.

When Face Matcher runs underneath Smart Corridors & e-Gates, the same file also needs that product's `smart_corridor` block. That is documented in the Smart Corridors repository; nothing about it changes here.
