#!/usr/bin/env python3
"""Fail CI when Slither analysis fails or changes outside the reviewed baseline."""

from collections import Counter
import json
import sys
from pathlib import Path


def normalize_source_mapping(mapping):
    """Keep all location fields needed to distinguish affected source elements."""
    if not isinstance(mapping, dict):
        return {}
    return {
        field: mapping.get(field)
        for field in (
            "filename_relative",
            "start",
            "length",
            "starting_column",
            "ending_column",
        )
        if field in mapping
    }


def normalize_parent(parent):
    """Keep the complete parent chain without repeating its source locations."""
    if not isinstance(parent, dict):
        return {}
    result = {
        field: parent[field]
        for field in ("type", "name", "signature")
        if field in parent
    }
    if "parent" in parent:
        result["parent"] = normalize_parent(parent["parent"])
    return result


def normalize(value):
    """Normalize auxiliary fields while removing machine-specific absolute paths."""
    if isinstance(value, dict):
        return {
            field: normalize(item)
            for field, item in sorted(value.items())
            if field not in {"filename_absolute", "filename_short", "is_dependency"}
        }
    if isinstance(value, list):
        return [normalize(item) for item in value]
    return value


def normalize_element(element):
    """Preserve every affected element, location, parent and detector detail."""
    type_specific_fields = element.get("type_specific_fields", {})
    normalized = {
        "type": element.get("type", ""),
        "name": element.get("name", ""),
        "source_mapping": normalize_source_mapping(element.get("source_mapping", {})),
        "type_specific_fields": {
            field: normalize_parent(item) if field == "parent" else normalize(item)
            for field, item in sorted(type_specific_fields.items())
        },
        "additional_fields": normalize(element.get("additional_fields", {})),
    }
    return normalized


def normalize_finding(detector):
    """Normalize the complete finding, including every affected element/location."""
    elements = [normalize_element(element) for element in detector.get("elements", [])]
    elements.sort(key=lambda element: json.dumps(element, sort_keys=True, separators=(",", ":")))
    return {
        "check": detector.get("check", ""),
        "impact": detector.get("impact", ""),
        "confidence": detector.get("confidence", ""),
        "elements": elements,
        "additional_fields": normalize(detector.get("additional_fields", {})),
    }


def serialized_findings(findings):
    """Serialize findings canonically so Counter preserves duplicate findings."""
    return Counter(
        json.dumps(finding, sort_keys=True, separators=(",", ":")) for finding in findings
    )


def print_counter(title, findings):
    print(title, file=sys.stderr)
    for serialized, count in sorted(findings.items()):
        print(f"  ({count}x) {serialized}", file=sys.stderr)


def main():
    if len(sys.argv) != 3:
        print("usage: check_slither_baseline.py REPORT BASELINE", file=sys.stderr)
        return 2

    report_path, baseline_path = map(Path, sys.argv[1:])
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Unable to read Slither evidence: {exc}", file=sys.stderr)
        return 2

    if report.get("success") is not True:
        print(f"Slither analysis did not complete successfully: {report.get('error')}", file=sys.stderr)
        return 1

    actual = [normalize_finding(detector) for detector in report.get("results", {}).get("detectors", [])]
    actual_counts = serialized_findings(actual)
    baseline_counts = serialized_findings(baseline)

    unexpected = actual_counts - baseline_counts
    missing = baseline_counts - actual_counts
    if unexpected or missing:
        if unexpected:
            print_counter("Unexpected Slither findings:", unexpected)
        if missing:
            print_counter(
                "Baseline findings no longer present; review and update the baseline:", missing
            )
        return 1

    print(f"Slither baseline passed: {len(actual)} reviewed findings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
