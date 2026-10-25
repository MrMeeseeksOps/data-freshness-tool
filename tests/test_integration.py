"""Opt-in read-only checks against a dedicated nonproduction metadata database."""

import os

import pytest

from freshness_monitor.config import Settings
from freshness_monitor.repository import Repository
from freshness_monitor.snowflake_client import SnowflakeClient


@pytest.mark.integration
@pytest.mark.skipif(
    os.environ.get("FRESHNESS_INTEGRATION") != "nonproduction",
    reason="Set FRESHNESS_INTEGRATION=nonproduction explicitly",
)
def test_nonproduction_connection_and_metadata():
    settings = Settings.from_env()
    client = SnowflakeClient(settings)
    rows, _ = client.query("SELECT CURRENT_VERSION() AS VERSION")
    assert rows[0]["version"]
    Repository(client, settings.database).monitors()
