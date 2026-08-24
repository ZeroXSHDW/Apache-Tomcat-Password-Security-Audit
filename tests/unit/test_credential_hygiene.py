"""Static contracts preventing patch scripts from leaking credentials."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UNIX_PATCH = ROOT / "src/unix/Patch/bash/UpdateTomcatUserUnix.sh"
WINDOWS_PATCH = ROOT / "src/windows/Patch/powershell/UpdateTomcatUserWin.ps1"


class TestCredentialHygiene(unittest.TestCase):
    def test_unix_patch_uses_argument_array_and_redacts_secret_output(self) -> None:
        source = UNIX_PATCH.read_text(encoding="utf-8")
        self.assertIn('"${digest_args[@]}"', source)
        self.assertIn("Aborting patch.", source)
        self.assertNotIn("Defaulting to 8.5", source)
        self.assertIn(
            "done < <(awk '/^[[:space:]]*<user / && $0 !~",
            source,
        )
        self.assertNotIn('local cmd="$digest', source)
        self.assertNotIn("Failed to generate hash for $password", source)
        self.assertNotIn('Old password:  $pw', source)
        self.assertNotIn('New password:  $hash', source)

    def test_windows_patch_does_not_log_digest_command_or_raw_output(self) -> None:
        source = WINDOWS_PATCH.read_text(encoding="utf-8")
        self.assertIn("& $digestScript @digestArgs", source)
        self.assertNotIn('Write-Log "Running digest.bat command:', source)
        self.assertNotIn('Write-Log "digest.bat output: $digestRaw', source)
        self.assertNotIn('$startInfo.Arguments = "/c', source)


if __name__ == "__main__":
    unittest.main()
