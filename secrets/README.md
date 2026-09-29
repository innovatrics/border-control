# secrets/ — licensed material (do NOT commit / publish)

Everything in this folder is **Innovatrics-licensed** and stays internal. The `.gitignore` at the repository root excludes `secrets/*.lic`; this README stays tracked.

One `iengine.lic`, tied to the hardware of the machine, is mounted into every service: the corridor services and the vendored Face Matcher underneath them. It must carry:

- the **iengine/IFace** block — used by the Face Matcher platform and by CIGS (hardware-bound);
- the **`smart_corridor`** block — used by the Hub (`smart_corridor.hub`) and the operational-display frontend (`smart_corridor.operational_display`), which are fail-closed gated.

| File | What | If missing / incomplete |
|---|---|---|
| `iengine.lic` | Hardware-bound Innovatrics license for the machine, with both blocks. | Any service whose block is absent refuses to start — the platform and CIGS on the iengine block, the Hub and frontend on the `smart_corridor` block. |

Put the file here and nowhere else. `start.sh` links it into `face-matcher/secrets/`, where Face Matcher's own scripts look for it, and Face Matcher links it on into its platform.
