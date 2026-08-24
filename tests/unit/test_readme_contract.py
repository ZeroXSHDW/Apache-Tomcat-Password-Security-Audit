import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReadmeContractTests(unittest.TestCase):
    def test_readme_exposes_unique_operator_sections(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        required = (
            "## Overview",
            "## Features",
            "## Architecture and boundaries",
            "## Prerequisites",
            "## Installation and setup",
            "## Quick Start",
            "## Usage",
            "## Command Line Parameters",
            "## Verification",
            "## Testing Framework",
            "## Configuration reference and recommendations",
            "## License",
            "## Contributing",
        )

        for heading in required:
            self.assertIn(heading, readme)

        headings = re.findall(r"^## .+$", readme, flags=re.MULTILINE)
        self.assertEqual(len(headings), len(set(headings)))
        self.assertNotRegex(readme, r"https://github\.com/your-org/")
        self.assertNotRegex(readme, r"/Users/|[A-Z]:\\Users\\")
        self.assertIn("git diff --check", readme)
        self.assertIn("## Security", readme)
        self.assertIn("git clone https://github.com/ZeroXSHDW/Apache-Tomcat-Password-Security-Audit ~/tomcat-audit", readme)
        self.assertIn("sudo bash ./src/unix/Audit/bash/CheckTomcatConfigUnixBash.sh", readme)
        self.assertIn("sudo bash ./src/unix/Patch/bash/UpdateTomcatUserUnix.sh", readme)
        self.assertEqual(
            workflow.count("git diff --check"),
            workflow.count("uses: actions/checkout@"),
        )


if __name__ == "__main__":
    unittest.main()
