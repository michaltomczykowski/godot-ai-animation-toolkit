"""Archive idle source CI, before review or after approved fixture migration."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
from archive_run_review import digest, read, require, write


def gh(*args: str) -> str:
    return subprocess.check_output(["gh", *args], text=True, encoding="utf-8", errors="replace")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--approved-regression", action="store_true",
                        help="Require green comparison of the reviewed v2 idle fixture")
    args = parser.parse_args()
    run = json.loads(gh("run", "view", str(args.run_id), "--json", "status,conclusion,headSha,url,jobs"))
    require(run["headSha"] == args.source and run["status"] == "completed", "Wrong or incomplete source CI")
    write(args.folder / "ci-source.json", run)
    editors, live = [], []
    for job in run["jobs"]:
        name = job["name"]
        if not name.startswith(("Editor suite /", "Live MCP route /")):
            continue
        raw = gh("run", "view", str(args.run_id), "--job", str(job["databaseId"]), "--log")
        path = args.folder / ("ci-job-" + str(job["databaseId"]) + ".log")
        path.write_text(raw, encoding="utf-8")
        item = {"name": name, "log": str(path), "sha256": digest(path)}
        checkouts = re.findall(r"Z ([a-f0-9]{40})(?:\r?\n|$)", raw)
        require(len(checkouts) == 2, "Missing toolkit/core checkout identity: " + name)
        item["core_source"] = checkouts[1]
        if name.endswith(" / core v4.2.1") or name.startswith("Live MCP route /"):
            require(item["core_source"] == "bfc264200584ea5823f18356acb164781f57796d",
                    "Pinned released core differs: " + name)
        if name.startswith("Editor suite /"):
            matches = re.findall(r"CI_SUITE_RESULTS=(\{[^\n]+\})", raw)
            require(len(matches) == 1, "Missing editor result: " + name)
            result = json.loads(matches[0])
            failures = [r for r in result["results"] if not r["passed"]]
            skips = [r for r in result["results"] if r.get("skipped")]
            expected_failures = [] if args.approved_regression else ["test_the_idle_matches_its_golden"]
            require(job["conclusion"] == ("success" if args.approved_regression else "failure")
                    and result["total"] == 389 and result["passed"] == (387 if args.approved_regression else 386)
                    and result["failed"] == len(expected_failures) and result["skipped"] == 2
                    and [r["test"] for r in failures] == expected_failures
                    and {r["test"] for r in skips} == {"test_responsive_default_aliases_and_setup_use_identical_walks",
                                                       "test_xbot_rooted_walk_and_run_play_with_contact"}
                    and not result["engine_errors"] and not result["discovery_errors"] and not result["tool_route_errors"]
                    and raw.count("CI_TOOL_ROUTE_PASS: 10 families, 103 operation dry-run routes") == 2,
                    "Unexpected editor result: " + name)
            if args.approved_regression:
                drift = re.findall(r"golden idle_cycle: worst drift (\d+) unit\(s\)", raw)
                require(len(drift) == 1 and int(drift[0]) <= 2,
                        "Missing approved idle comparison within digest tolerance: " + name)
                item["idle_golden_drift_units"] = int(drift[0])
            item.update(total=result["total"], passed=result["passed"], failed=result["failed"], skipped=2,
                        failures=failures, skips=skips, engine_errors=0, route_pass_markers=2)
            write(path.with_suffix(".json"), result)
            editors.append(item)
        else:
            passed = len(re.findall(r"MCP_CI_PASS=", raw))
            failed = len(re.findall(r"MCP_CI_FAIL=", raw))
            require(job["conclusion"] == "success" and passed == 118 and failed == 0, "Unexpected live MCP result: " + name)
            item.update(pass_markers=passed, fail_markers=failed)
            live.append(item)
    tiers = [j for j in run["jobs"] if j["name"].startswith("Tier 1 /")]
    require(len(tiers) == 28 and all(j["conclusion"] == "success" for j in tiers)
            and len(editors) == 4 and len(live) == 2, "Incomplete source CI matrix")
    require({j["name"] for j in editors} == {
        f"Editor suite / {platform} / core {core}"
        for platform in ("ubuntu-latest", "windows-latest") for core in ("v4.2.1", "main")},
        "Missing pinned or advisory editor job")
    require({j["name"] for j in live} == {
        "Live MCP route / ubuntu-latest", "Live MCP route / windows-latest"},
        "Missing platform live route")
    # CI checks out GitHub's synthetic merge; prove its tracked tree equals source.
    merge = re.findall(r"HEAD is now at ([a-f0-9]+) Merge " + re.escape(args.source), Path(editors[0]["log"]).read_text(encoding="utf-8"))
    require(len(merge) == 1, "Missing tested merge checkout")
    repo_slug = "michaltomczykowski/godot-ai-animation-toolkit"
    tested = json.loads(gh("api", f"repos/{repo_slug}/commits/{merge[0]}"))
    local_tree = subprocess.check_output(["git", "rev-parse", args.source + "^{tree}"], cwd=args.repo, text=True).strip()
    require(tested["commit"]["tree"]["sha"] == local_tree, "CI merge tree differs from source")
    receipt = {"source_head": args.source, "tested_merge": tested["sha"], "tracked_tree_matches_source": True,
               "run_id": args.run_id, "url": run["url"], "status": run["status"], "conclusion": run["conclusion"],
               "expected_legacy_idle_golden_only": not args.approved_regression,
               "approved_idle_regression": args.approved_regression,
               "all_other_source_jobs_pass": True,
               "all_required_source_jobs_pass": args.approved_regression,
               "all_advisory_jobs_pass": args.approved_regression,
               "headless_jobs": 28, "editor_jobs": editors, "live_mcp_jobs": live,
               "release_ready": False, "archived_utc": datetime.now(timezone.utc).isoformat()}
    write(args.folder / "ci-receipt.json", receipt)
    print("IDLE_SOURCE_CI=28 headless and 2 live pass; " + (
        "4 editors compare the approved idle within digest tolerance with only named private-rig skips"
        if args.approved_regression else "4 editors have only preserved idle golden and private-rig skips"))


if __name__ == "__main__":
    main()
