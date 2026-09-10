# secrets/ — licensed material (do NOT commit / publish)

Everything in this folder is **Innovatrics-licensed** and stays internal. The `.gitignore` at the stack root excludes this whole directory.

A **single** `iengine.lic` is mounted into every service. It must carry:
- the **iengine/IFace** block — used by the SmartFace/VPP platform and CIGS (hardware-bound);
- the **`smart_corridor`** block — used by the Hub (`smart_corridor.hub`) and the operational-display
  frontend (`smart_corridor.operational_display`), which are fail-closed gated.

| File | What | If missing / incomplete |
|---|---|---|
| `iengine.lic` | Universal Innovatrics license for the whole stack (iengine + `smart_corridor` blocks). | Any service whose block is absent refuses to start — the platform/CIGS on the iengine block, the Hub and frontend on the `smart_corridor` block. |
