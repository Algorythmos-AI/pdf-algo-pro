"""Tests for ios_gate.py: a table of the cases that matter, then every combination of job results.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import itertools
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ios_gate  # noqa: E402

RESULTS = ("success", "failure", "cancelled", "skipped")
S, F, C, K = RESULTS


def needs(changes=S, ios="true", build=S, device=S, tests=S, report=S, export=None, validation=None) -> dict:
    """The jobs' results. The PDF jobs follow ios-report unless given: skipped when it is, else success."""
    outputs = {} if ios is None else {"ios": ios}
    export = export if export is not None else (K if report == K else S)
    validation = validation if validation is not None else (K if export in (K, F, C) else S)
    return {"changes": {"result": changes, "outputs": outputs}, "ios-build": {"result": build, "outputs": {}},
            "ios-device": {"result": device, "outputs": {}}, "ios-tests": {"result": tests, "outputs": {}},
            "ios-report": {"result": report, "outputs": {}}, "pdf-export": {"result": export, "outputs": {}},
            "pdf-validation": {"result": validation, "outputs": {}}}


@pytest.mark.parametrize("case,only_testing,passes", [
    # Change detection
    (needs(changes=F, ios=None, build=K, device=K, tests=K, report=K), "", False),
    (needs(changes=C, ios=None, build=K, device=K, tests=K, report=K), "", False),
    (needs(changes=K, ios=None, build=K, device=K, tests=K, report=K), "", False),
    (needs(ios=None, build=K, device=K, tests=K, report=K), "", False),
    (needs(ios="", build=K, device=K, tests=K, report=K), "", False),
    (needs(ios="yes"), "", False),
    # Nothing to run
    (needs(ios="false", build=K, device=K, tests=K, report=K), "", True),
    (needs(ios="false", build=F, device=K, tests=K, report=K), "", False),
    (needs(ios="false", build=K, device=K, tests=K, report=S), "", False),
    # Full run
    (needs(), "", True),
    (needs(build=F, tests=K, report=K), "", False),
    (needs(device=F), "", False),
    (needs(tests=F), "", False),
    (needs(report=F), "", False),
    (needs(report=K), "", False),
    (needs(device=K), "", False),
    (needs(tests=C, report=K), "", False),
    # The PDF jobs (required since R2: no longer advisory)
    (needs(export=F), "", False),
    (needs(validation=F), "", False),
    (needs(validation=C), "", False),
    (needs(export=K, validation=K), "", False),
    (needs(validation=K), "", False),
    (needs(ios="false", build=K, device=K, tests=K, report=K, export=S, validation=K), "", False),
    (needs(ios="false", build=K, device=K, tests=K, report=K, export=K, validation=F), "", False),
    # Focused run
    (needs(device=K, report=K), "PDFAlgoProUITests/ReaderUITests", True),
    (needs(device=S, report=K), "PDFAlgoProUITests/ReaderUITests", True),
    (needs(device=F, report=K), "PDFAlgoProUITests/ReaderUITests", False),
    (needs(device=K, report=S), "PDFAlgoProUITests/ReaderUITests", False),
    (needs(device=K, tests=F, report=K), "PDFAlgoProUITests/ReaderUITests", False),
    (needs(device=K, build=F, tests=K, report=K), "PDFAlgoProUITests/ReaderUITests", False),
    (needs(device=K, report=K), "   ", False),  # blank only_testing is a full run, which needs every job
    (needs(device=K, report=K, export=S, validation=S), "PDFEngineTests/SaveFaultTests", True),
    (needs(device=K, report=K, export=F, validation=K), "PDFEngineTests/SaveFaultTests", False),
    (needs(device=K, report=K, export=S, validation=F), "PDFEngineTests/SaveFaultTests", False),
])
def test_table(case, only_testing, passes):
    assert ios_gate.verdict(case, only_testing)[0] is passes


@pytest.mark.parametrize("only_testing", ["", "CoreTests"])
@pytest.mark.parametrize("ios", ["true", "false", "", None])
@pytest.mark.parametrize("changes", RESULTS)
def test_every_combination(changes, ios, only_testing):
    for build, device, tests, report, export, validation in itertools.product(RESULTS, repeat=6):
        case = needs(changes, ios, build, device, tests, report, export, validation)
        passes, problems = ios_gate.verdict(case, only_testing)
        jobs = {"ios-build": build, "ios-device": device, "ios-tests": tests, "ios-report": report,
                "pdf-export": export, "pdf-validation": validation}
        assert passes is (not problems)
        if changes != S or ios not in ("true", "false"):
            assert not passes
        elif ios == "false":
            assert passes is all(r == K for r in jobs.values())
        elif not only_testing:
            assert passes is all(r == S for r in jobs.values())
        else:
            assert passes is (build == S and tests == S and report == K
                              and all(r in (S, K) for r in (device, export, validation)))
        if F in jobs.values() or C in jobs.values():
            assert not passes, f"green with a failed or cancelled job: {jobs}"


def test_a_missing_job_fails():
    case = needs()
    del case["ios-report"]
    passes, problems = ios_gate.verdict(case, "")
    assert not passes and "ios-report ended with 'missing'" in problems


@pytest.mark.parametrize("job", ["pdf-export", "pdf-validation"])
def test_a_missing_or_failed_pdf_job_fails_the_gate(job):
    """The PDF jobs are part of the gate: one left out of `needs`, or failed, turns `ios` red."""
    case = needs()
    del case[job]
    passes, problems = ios_gate.verdict(case, "")
    assert not passes and f"{job} ended with 'missing'" in problems
    case = needs()
    case[job]["result"] = F
    passes, problems = ios_gate.verdict(case, "")
    assert not passes and f"{job} ended with 'failure'" in problems


def test_main_reads_the_environment_and_writes_the_summary(tmp_path, capsys):
    summary = tmp_path / "summary.md"
    env = {"NEEDS_JSON": json.dumps(needs(tests=F)), "ONLY_TESTING": "", "GITHUB_STEP_SUMMARY": str(summary)}
    assert ios_gate.main(env) == 1
    out = capsys.readouterr().out
    assert "| ios-tests | failure |" in out and "::error::ios-tests ended with 'failure'" in out
    assert "ios-tests ended with 'failure'" in summary.read_text()
    assert ios_gate.main({"NEEDS_JSON": json.dumps(needs())}) == 0
    assert ios_gate.main({"NEEDS_JSON": "not json"}) == 1
    assert ios_gate.main({}) == 1
