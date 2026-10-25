from dataclasses import replace

import pytest

from freshness_monitor.config import Settings


def test_invalid_monitors(monitor):
    for changes in (
        {"critical_threshold_minutes": 30},
        {"strategy": "ROW_COUNT"},
        {"check_interval_minutes": 0},
        {"warning_threshold_minutes": float("nan")},
        {"expected_arrival": "{}"},
    ):
        with pytest.raises(ValueError):
            replace(monitor, **changes)


def test_settings(monkeypatch):
    for key in ("ACCOUNT", "USER", "ROLE", "WAREHOUSE", "PRIVATE_KEY_FILE"):
        monkeypatch.setenv("FRESHNESS_" + key, "example")
    assert Settings.from_env().workers == 4
    monkeypatch.setenv("FRESHNESS_WORKERS", "99")
    with pytest.raises(ValueError):
        Settings.from_env()


def test_missing_settings(monkeypatch):
    monkeypatch.delenv("FRESHNESS_ACCOUNT", raising=False)
    with pytest.raises(ValueError):
        Settings.from_env()
