"""Validate the complete Compose wiring without licenses, images or a running daemon.

Run: python3 -m unittest discover -s tests -v
"""

import json
import os
from pathlib import Path
import subprocess
import unittest
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
MATCHER = ROOT / "face-matcher"
PLATFORM = MATCHER / "platform"
CORRIDOR = ROOT / "smart-corridors-and-e-gates"

# Smart Corridors runs Station out of the Face Matcher module with its own brand and without
# Station's 1:N Identification page. start.sh exports exactly these.
CORRIDOR_STATION_ENV = {
    "STATION_BRANDING": "../smart-corridors-and-e-gates/branding/station",
    "STATION_IDENTIFICATION": "false",
}


def compose(directory, *args, env=None):
    result = subprocess.run(
        ["docker", "compose", *args, "config", "--format", "json"],
        cwd=directory, text=True, capture_output=True, check=True,
        env={**os.environ, **env} if env else None,
    )
    return json.loads(result.stdout)


class DeploymentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.corridor = compose(CORRIDOR, "-f", "docker-compose.yml", "--env-file", ".env")
        cls.station = compose(MATCHER, "-f", "docker-compose.yml", "--env-file", ".env")
        cls.platform = compose(PLATFORM)  # Includes the restart-policy override.
        cls.dependencies = compose(PLATFORM, "-f", "dependencies/docker-compose.yml")
        cls.mct_args = ("-p", "sceg-mct", "-f", "mct/docker-compose.yml", "--env-file", ".env.mct")
        cls.mct = compose(CORRIDOR, *cls.mct_args, "--profile", "*")
        cls.projects = (cls.corridor, cls.station, cls.platform, cls.dependencies, cls.mct)

    def test_internal_hosts_share_one_network(self):
        networks = {p["networks"]["default"]["name"] for p in self.projects}
        self.assertEqual(len(networks), 1, networks)
        hosts = set()
        for project in self.projects:
            for name, service in project["services"].items():
                hosts.add(name)
                if "container_name" in service:
                    hosts.add(service["container_name"])
                hosts.update((service.get("networks", {}).get("default") or {}).get("aliases", []))
        for project in (self.corridor, self.station):
            for name, service in project["services"].items():
                for key, value in service.get("environment", {}).items():
                    if key in {"HUB_URL", "SMARTFACE_GQL_URL", "SMARTFACE_API_URL",
                               "SMARTFACE_STATION_URL", "STORAGE_S3_ENDPOINT",
                               "CORE_API_ROOT", "GRAPHQL_ROOT", "S3_ENDPOINT"}:
                        self.assertIn(urlparse(value).hostname, hosts, (name, key, value))
                    elif key.endswith("GRAPHQL_HOST") or key == "RABBITMQ_HOST":
                        self.assertIn(value, hosts, (name, key, value))

    def test_one_license_serves_every_module(self):
        sources = set()
        for project, names in ((self.corridor, ("hub", "cigs", "frontend")),
                               (self.station, ("sf-station",))):
            for name in names:
                mounts = [v for v in project["services"][name]["volumes"]
                          if v["target"] == "/etc/innovatrics/iengine.lic"]
                self.assertEqual(len(mounts), 1, name)
                self.assertTrue(mounts[0]["read_only"], name)
                sources.add(Path(mounts[0]["source"]))
        self.assertEqual(sources, {ROOT / "secrets" / "iengine.lic"})

    def test_station_branding_is_overridable_per_module(self):
        """Station lives in Face Matcher; a module on top swaps the brand assets, not the file."""
        expected = {
            MATCHER: compose(MATCHER, "-f", "docker-compose.yml", "--env-file", ".env"),
            CORRIDOR: compose(MATCHER, "-f", "docker-compose.yml", "--env-file", ".env",
                              env=CORRIDOR_STATION_ENV),
        }
        for module, config in expected.items():
            station = config["services"]["sf-station"]
            branding = [v for v in station["volumes"]
                        if v["target"].startswith("/build/branding/")]
            self.assertEqual(len(branding), 4, module)
            for mount in branding:
                source = Path(mount["source"])
                self.assertEqual(source.parent, module / "branding" / "station", mount)
                self.assertTrue(source.is_file(), source)

    def test_station_identification_page_defaults_on_and_off_for_corridors(self):
        def identification(config):
            return str(config["services"]["sf-station"]["environment"]["IDENTIFICATION_ENABLED"])
        self.assertEqual(identification(self.station), "true")
        corridor_station = compose(MATCHER, "-f", "docker-compose.yml", "--env-file", ".env",
                                   env=CORRIDOR_STATION_ENV)
        self.assertEqual(identification(corridor_station), "false")

    def test_corridor_module_starts_face_matcher_underneath(self):
        """Face Matcher is a required part of Smart Corridors, not an optional extra."""
        for script in ("start.sh", "stop.sh", "factory-reset.sh"):
            body = (CORRIDOR / script).read_text(encoding="utf-8")
            self.assertIn(f"cd ../face-matcher && bash {script}", body, script)
        self.assertIn("STATION_BRANDING", (CORRIDOR / "start.sh").read_text(encoding="utf-8"))

    def test_face_matcher_drops_the_functionality_it_removed(self):
        """Offline video processing, grouping and palm biometrics are not part of Face Matcher."""
        removed = {"grouping", "video-reader", "video-collector", "video-aggregator",
                   "palm-detector", "palm-extractor"}
        for project in (self.platform, self.station, self.corridor):
            self.assertEqual(removed & set(project["services"]), set())
        for script in ("migrate-palms.sh", "finalize-non-migrated-palms.sh"):
            self.assertFalse((PLATFORM / script).exists(), script)
        settings = (PLATFORM / ".env").read_text(encoding="utf-8")
        for key in ("PalmValidation__", "Grouping__", "Aggregation__", "VideoRecordCollecting__"):
            self.assertNotIn(key, settings)

    def test_mct_is_opt_in(self):
        for project in (self.corridor, self.station, self.platform, self.dependencies):
            for service in project["services"].values():
                self.assertNotIn("/mct-", service["image"])
        environment = self.corridor["services"]["hub"]["environment"]
        self.assertNotEqual(str(environment.get("ZONE_MCT_ENABLED", "false")).lower(), "true")

    def test_platform_api_ports_match_clients(self):
        corridor = self.corridor["services"]
        station = self.station["services"]["sf-station"]["environment"]
        graphql_port = str(self.platform["services"]["graphql-api"]["environment"]["Hosting__Port"])
        api_port = int(self.platform["services"]["api"]["environment"]["Hosting__Port"])
        self.assertEqual(str(corridor["hub"]["environment"]["VPP_GRAPHQL_PORT"]), graphql_port)
        self.assertEqual(str(corridor["cigs"]["environment"]["CORRIDOR_IDENTITY_GROUPING_SOURCE_GRAPHQL_PORT"]), graphql_port)
        self.assertEqual(urlparse(corridor["frontend"]["environment"]["SMARTFACE_GQL_URL"]).port, int(graphql_port))
        self.assertEqual(urlparse(corridor["frontend"]["environment"]["SMARTFACE_API_URL"]).port, api_port)
        self.assertEqual(urlparse(station["GRAPHQL_ROOT"]).port, int(graphql_port))
        self.assertEqual(urlparse(station["CORE_API_ROOT"]).port, api_port)

    def test_corridor_frontend_reaches_station(self):
        url = self.corridor["services"]["frontend"]["environment"]["SMARTFACE_STATION_URL"]
        station = self.station["services"]["sf-station"]
        self.assertEqual(urlparse(url).hostname, station["container_name"])
        self.assertIn(urlparse(url).port, [int(p["target"]) for p in station["ports"]])

    def test_mount_targets_are_unique(self):
        for project in self.projects:
            for name, service in project["services"].items():
                targets = [v["target"] for v in service.get("volumes", [])]
                self.assertEqual(len(targets), len(set(targets)), name)

    def test_mct_startup_profiles_and_persistence(self):
        for profile in (None, "migrate", "seed"):
            args = ("--profile", profile) if profile else ()
            config = compose(CORRIDOR, *self.mct_args, *args)
            self.assertIn("configurationApi", config["services"])
        services = self.mct["services"]
        for dependent, dependency in (("configurationApi", "postgres"),
                                     ("trackingService", "configurationApi")):
            self.assertEqual(services[dependent]["depends_on"][dependency]["condition"],
                             "service_healthy")
        self.assertIn("seed", services["configApiSeeder"]["profiles"])
        self.assertIn("migrate", services["dbMigrator"]["profiles"])
        self.assertTrue(services["postgres"]["image"].startswith("postgres:"))
        self.assertIn("/data:mode=1777", services["trackingService"]["tmpfs"])
        for name, service in services.items():
            if service["image"].startswith("registry.dot.innovatrics.com/"):
                self.assertEqual(service["platform"], "linux/amd64", name)

    def test_autoheal_only_targets_this_stack(self):
        services = self.corridor["services"]
        label = services["autoheal"]["environment"]["AUTOHEAL_CONTAINER_LABEL"]
        self.assertNotIn(label, ("all", "autoheal"))
        for name in ("cigs", "frontend"):
            self.assertEqual(services[name]["labels"][label], "true")
            self.assertIn("healthcheck", services[name])

    def test_frontend_refreshes_after_hub_recreation(self):
        dependency = self.corridor["services"]["frontend"]["depends_on"]["hub"]
        self.assertEqual(dependency["condition"], "service_started")
        self.assertTrue(dependency["restart"])

    def test_shell_syntax(self):
        scripts = [p for module in (MATCHER, CORRIDOR) for p in module.rglob("*.sh")]
        self.assertTrue(scripts)
        for path in scripts:
            subprocess.run(["bash", "-n", str(path)], check=True)


if __name__ == "__main__":
    unittest.main()
