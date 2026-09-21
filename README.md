# Innovatrics Border Control cluster

Multi-module repository. Each folder below is a module: a runnable Docker Compose deployment with its own configuration, scripts and documentation.

| Module | Folder | What it does |
| ------ | ------ | ------------ |
| Face Matcher | [`face-matcher/`](face-matcher/) | Real-time face identification. Cameras in, identified faces out, with watchlists, an operator UI and REST/GraphQL APIs. Deploy it on its own, or as the base of another module. |
| Smart Corridors & e-Gates | [`smart-corridors-and-e-gates/`](smart-corridors-and-e-gates/) | Corridor and e-gate clearance: per-traveller identity grouping, clearance decisions and an operational display. Builds on Face Matcher. |

## How they fit together

Face Matcher is the base module. It owns the face pipeline, the database, the message broker, the blob storage and the shared `fm-network` that everything else joins.

Smart Corridors & e-Gates adds the corridor services on top and starts Face Matcher for you, so its quick start is the only one you need to follow if corridors are what you are deploying. Running the two modules side by side on one host is not a thing: the second one is already inside the first.

```
smart-corridors-and-e-gates/   Hub · CIGS · operational display   (+ optional MCT overlay)
face-matcher/                  platform (engine, APIs, cameras) · Station
secrets/                       one iengine.lic for the machine
```

## Getting started

1. Clone this repository onto the target machine.
2. Log in to the Innovatrics Harbor registry — see the module README for the command.
3. Put your `iengine.lic` in [`secrets/`](secrets/).
4. Run the start script of the module you want: `face-matcher/start.sh`, or `smart-corridors-and-e-gates/start.sh` for the full corridor stack.

Licensing, registry access and the per-module configuration are documented in [`face-matcher/README.md`](face-matcher/README.md) and [`smart-corridors-and-e-gates/README.md`](smart-corridors-and-e-gates/README.md).
