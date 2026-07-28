"""Self-contained unit tests for Unix Tomcat config test helpers.

These do not require a Tomcat install. The full lab harness in
`tests/Audit/unix/test_config_unix.py` still needs a real Tomcat tree.
"""
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HELPERS = Path(__file__).resolve().parents[1] / "Audit" / "unix" / "test_config_unix.py"


def _load_module(home: Path):
    spec = importlib.util.spec_from_file_location("test_config_unix", HELPERS)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {HELPERS}")
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, {"HOME": str(home)}):
        # Re-bind expanduser target used at module import for the log path.
        with mock.patch("os.path.expanduser", side_effect=lambda p: str(home / p.lstrip("~/"))):
            spec.loader.exec_module(module)
    return module


class TestXmlHelpers(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmpdir = tempfile.TemporaryDirectory()
        home = Path(cls._tmpdir.name)
        cls.mod = _load_module(home)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmpdir.cleanup()

    def test_validate_well_formed_xml(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "server.xml"
            path.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                "<Server><Service/></Server>\n",
                encoding="utf-8",
            )
            self.assertTrue(self.mod.validate_xml_structure(str(path)))

    def test_reject_missing_xml_declaration(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.xml"
            path.write_text("<Server/>\n", encoding="utf-8")
            self.assertFalse(self.mod.validate_xml_structure(str(path)))

    def test_reject_missing_file(self) -> None:
        self.assertFalse(self.mod.validate_xml_structure("/no/such/file.xml"))

    def test_secure_parse_and_write_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "tomcat-users.xml"
            path.write_text(
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<tomcat-users><user username="a" password="x" roles="manager"/></tomcat-users>\n',
                encoding="utf-8",
            )
            tree = self.mod.secure_parse_xml(str(path))
            self.assertIsNotNone(tree)
            root = tree.getroot()
            user = root.find(".//user")
            self.assertIsNotNone(user)
            user.set("password", "hashedvalue")
            self.assertTrue(self.mod.secure_write_xml(str(path), tree))
            again = self.mod.secure_parse_xml(str(path))
            self.assertEqual(again.getroot().find(".//user").get("password"), "hashedvalue")


if __name__ == "__main__":
    unittest.main()
