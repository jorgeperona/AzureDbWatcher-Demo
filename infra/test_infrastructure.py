"""Offline infrastructure contract checks; no Azure connection."""

import re
import json
import subprocess
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


class InfrastructureTests(unittest.TestCase):
    def test_subscription_scope_creates_group_and_scopes_module(self):
        main = (HERE / "main.bicep").read_text()
        self.assertIn("targetScope = 'subscription'", main)
        self.assertIn("resource controlGroup 'Microsoft.Resources/resourceGroups@", main)
        self.assertIn("scope: controlGroup", main)
        self.assertIn("module control './modules/control.bicep'", main)

    def test_all_required_parameters_are_supplied(self):
        main = (HERE / "main.bicep").read_text()
        parameters = (HERE / "main.bicepparam").read_text()
        self.assertEqual(
            set(re.findall(r"^param (\w+) ", main, re.MULTILINE)),
            set(re.findall(r"^param (\w+) =", parameters, re.MULTILINE)),
        )
        self.assertNotRegex(main + parameters, r"(?m)^(?:param|var) \w*[Tt]enant\w* ")
        module = (HERE / "modules/control.bicep").read_text()
        self.assertEqual(
            set(re.findall(r"^param (\w+) ", module, re.MULTILINE)),
            set(re.findall(r"^    (\w+):", main.split("  params: {", 1)[1].split("\n  }", 1)[0], re.MULTILINE)),
        )

    def test_server_is_created_public_with_entra_only_and_tls(self):
        module = (HERE / "modules/control.bicep").read_text()
        self.assertRegex(module, r"resource controlServer 'Microsoft.Sql/servers@[^']+' =")
        self.assertIn("publicNetworkAccess: 'Enabled'", module)
        self.assertIn("azureADOnlyAuthentication: true", module)
        self.assertIn("tenantId: subscription().tenantId", module)
        self.assertIn("minimalTlsVersion: '1.2'", module)
        self.assertNotIn("administratorLoginPassword", module)
        self.assertIn("if (allowAzureServices)", module)
        self.assertIn("for rule in administratorFirewallRules", module)

    def test_private_network_resources_and_bootstrap_are_removed(self):
        for path in HERE.rglob("*.bicep"):
            self.assertNotRegex(
                path.read_text(),
                r"Microsoft.Network/|Microsoft.Sql/servers/jobAgents/privateEndpoints",
            )
        parameters = (HERE / "main.bicepparam").read_text()
        self.assertNotIn("privateEndpoint", parameters)
        self.assertNotIn("administrationVnet", parameters)
        self.assertFalse((HERE / "create-control-server.sh").exists())

    def test_only_mandatory_local_database_backup_remains(self):
        main = (HERE / "main.bicep").read_text()
        parameters = (HERE / "main.bicepparam").read_text()
        module = (HERE / "modules/control.bicep").read_text()
        self.assertNotIn("jobDatabaseBackupRedundancy", main + parameters + module)
        self.assertIn("requestedBackupStorageRedundancy: 'Local'", module)
        self.assertNotIn("longTermRetentionPolicies", module)

    def test_documentation_links_resolve(self):
        for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", (HERE / "README.md").read_text()):
            if "://" not in target:
                self.assertTrue((HERE / target.split("#")[0]).exists(), target)

    def test_environment_example_supplies_every_required_variable(self):
        parameters = (HERE / "main.bicepparam").read_text()
        required = set(re.findall(r"readEnvironmentVariable\('([^']+)'\)", parameters))
        example = HERE / ".env.example"
        supplied = set(re.findall(r"^([A-Z_][A-Z_0-9]*)=", example.read_text(), re.MULTILINE))
        self.assertEqual(required, supplied)
        result = subprocess.run(
            ["bash", "-c", 'set -a; source "$1"; set +a; python3 -c \'import json,os; print(json.dumps(dict(os.environ)))\'', "test", str(example)],
            capture_output=True, text=True, check=True,
        )
        values = json.loads(result.stdout)
        self.assertIsInstance(json.loads(values["RESOURCE_TAGS_JSON"]), dict)
        self.assertIsInstance(json.loads(values["ALLOW_AZURE_SERVICES"]), bool)
        self.assertIsInstance(json.loads(values["ADMIN_FIREWALL_RULES_JSON"]), list)
        for suffix in ("01", "02"):
            self.assertTrue(values[f"STRESS_SERVER_{suffix}"])
            self.assertTrue(values[f"STRESS_DATABASE_{suffix}"])
        self.assertEqual(parameters.count("/subscriptions/${stressSubscriptionId}/resourceGroups/${stressResourceGroup}/providers/Microsoft.Sql/servers/"), 2)

    def test_local_environment_is_ignored_but_example_is_not(self):
        result = subprocess.run(
            ["git", "check-ignore", "--no-index", ".env", "infra/.env", ".env.local"],
            cwd=HERE.parent, capture_output=True, text=True, check=True,
        )
        self.assertEqual(set(result.stdout.splitlines()), {".env", "infra/.env", ".env.local"})
        example = subprocess.run(
            ["git", "check-ignore", "--no-index", "infra/.env.example"],
            cwd=HERE.parent, capture_output=True, text=True, check=False,
        )
        self.assertEqual(example.returncode, 1)


if __name__ == "__main__":
    unittest.main()
