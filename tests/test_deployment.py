"""Validate the complete Compose wiring without licenses, images or a running daemon.

Run: python3 -m unittest discover -s tests -v
"""

import json
from pathlib import Path
import subprocess
import unittest
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
STACK = ROOT / "smart-corridors-and-e-gates"


def compose(directory, *args):
    result = subprocess.run(
        ["docker", "compose", *args, "config", "--format", "json"],
        cwd=directory, text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)


class DeploymentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.corridor = compose(STACK, "-f", "docker-compose.yml", "--env-file", ".env")
        cls.vpp = compose(STACK / "vpp")  # Includes the restart-policy override.
        cls.dependencies = compose(STACK / "vpp", "-f", "dependencies/docker-compose.yml")
        cls.mct_args = ("-p", "sceg-mct", "-f", "mct/docker-compose.yml", "--env-file", ".env.mct")
        cls.mct = compose(STACK, *cls.mct_args, "--profile", "*")
        cls.projects = (cls.corridor, cls.vpp, cls.dependencies, cls.mct)

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
        for name, service in self.corridor["services"].items():
            for key, value in service.get("environment", {}).items():
                if key in {"HUB_URL", "SMARTFACE_GQL_URL", "SMARTFACE_API_URL",
                           "SMARTFACE_STATION_URL", "STORAGE_S3_ENDPOINT"}:
                    self.assertIn(urlparse(value).hostname, hosts, (name, key, value))
                elif key.endswith("GRAPHQL_HOST") or key == "RABBITMQ_HOST":
                    self.assertIn(value, hosts, (name, key, value))

    def test_license_and_branding_mounts(self):
        services = self.corridor["services"]
        sources = set()
        for name in ("hub", "cigs", "frontend", "sf-station"):
            mounts = [v for v in services[name]["volumes"]
                      if v["target"] == "/etc/innovatrics/iengine.lic"]
            self.assertEqual(len(mounts), 1, name)
            self.assertTrue(mounts[0]["read_only"], name)
            sources.add(mounts[0]["source"])
        self.assertEqual(len(sources), 1)
        branding = [v for v in services["sf-station"]["volumes"]
                    if v["target"].startswith("/build/branding/")]
        self.assertEqual(len(branding), 4)
        for mount in branding:
            self.assertTrue(Path(mount["source"]).is_file(), mount["source"])

    def test_mct_is_opt_in(self):
        for project in (self.corridor, self.vpp, self.dependencies):
            for service in project["services"].values():
                self.assertNotIn("/mct-", service["image"])
        environment = self.corridor["services"]["hub"]["environment"]
        self.assertNotEqual(str(environment.get("ZONE_MCT_ENABLED", "false")).lower(), "true")

    def test_vpp_api_ports_match_clients(self):
        services = self.corridor["services"]
        graphql_port = str(self.vpp["services"]["graphql-api"]["environment"]["Hosting__Port"])
        api_port = int(self.vpp["services"]["api"]["environment"]["Hosting__Port"])
        self.assertEqual(str(services["hub"]["environment"]["VPP_GRAPHQL_PORT"]), graphql_port)
        self.assertEqual(str(services["cigs"]["environment"]["CORRIDOR_IDENTITY_GROUPING_SOURCE_GRAPHQL_PORT"]), graphql_port)
        for name, key in (("frontend", "SMARTFACE_GQL_URL"), ("sf-station", "GRAPHQL_ROOT")):
            self.assertEqual(urlparse(services[name]["environment"][key]).port, int(graphql_port))
        for name, key in (("frontend", "SMARTFACE_API_URL"), ("sf-station", "CORE_API_ROOT")):
            self.assertEqual(urlparse(services[name]["environment"][key]).port, api_port)

    def test_mount_targets_are_unique(self):
        for project in self.projects:
            for name, service in project["services"].items():
                targets = [v["target"] for v in service.get("volumes", [])]
                self.assertEqual(len(targets), len(set(targets)), name)

    def test_mct_startup_profiles_and_persistence(self):
        for profile in (None, "migrate", "seed"):
            args = ("--profile", profile) if profile else ()
            config = compose(STACK, *self.mct_args, *args)
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
        for path in STACK.rglob("*.sh"):
            subprocess.run(["bash", "-n", str(path)], check=True)


if __name__ == "__main__":
    unittest.main()
