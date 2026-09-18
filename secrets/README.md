# secrets/ — licensed material (do NOT commit / publish)

Everything in this folder is **Innovatrics-licensed** and stays internal. The `.gitignore` at the repository root excludes `secrets/*.lic`; this README stays tracked.

One `iengine.lic` covers the whole machine and is mounted into every service of every module. It must carry:

- the **iengine/IFace** block — used by the Face Matcher platform and by CIGS (hardware-bound);
- the **`smart_corridor`** block — used by the Smart Corridors Hub (`smart_corridor.hub`) and the operational-display frontend (`smart_corridor.operational_display`), which are fail-closed gated.

A Face Matcher-only deployment needs the iengine block alone. Add the `smart_corridor` block when you also run Smart Corridors & e-Gates.

| File | What | If missing / incomplete |
|---|---|---|
| `iengine.lic` | Universal Innovatrics license for the machine (iengine + optional `smart_corridor` blocks). | Any service whose block is absent refuses to start — the platform and CIGS on the iengine block, the Hub and frontend on the `smart_corridor` block. |

`face-matcher/start.sh` symlinks this file to `face-matcher/platform/iengine.lic`, where the platform's own `run.sh` expects it.
