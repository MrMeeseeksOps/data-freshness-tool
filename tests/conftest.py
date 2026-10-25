from datetime import UTC, datetime
from unittest.mock import Mock

import pytest

from freshness_monitor.config import Monitor, Settings


@pytest.fixture
def monitor():
    return Monitor(101, "PROD", "PUBLIC", "ORDERS", "LOADED_AT", 60, 120)


@pytest.fixture
def now():
    return datetime(2026, 1, 1, tzinfo=UTC)


@pytest.fixture
def client():
    return Mock()


@pytest.fixture
def settings(tmp_path):
    return Settings(
        "account", "user", "role", "wh", "key.p8", metrics_file=tmp_path / "freshness.prom"
    )
