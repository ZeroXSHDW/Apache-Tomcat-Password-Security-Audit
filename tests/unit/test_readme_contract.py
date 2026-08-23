import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReadmeContractTests(unittest.TestCase):
    def test_readme_exposes_unique_operator_sections(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        required = (
            "## Overview",
            "## Architecture and boundaries",
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


if __name__ == "__main__":
    unittest.main()
