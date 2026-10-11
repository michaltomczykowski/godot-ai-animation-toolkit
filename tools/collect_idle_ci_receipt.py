"""Archive and verify the expected pre-review idle CI result from GitHub."""
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
        if name.startswith("Editor suite /"):
            matches = re.findall(r"CI_SUITE_RESULTS=(\{[^\n]+\})", raw)
            require(len(matches) == 1, "Missing editor result: " + name)
            result = json.loads(matches[0])
            failures = [r for r in result["results"] if not r["passed"]]
            skips = [r for r in result["results"] if r.get("skipped")]
            require(job["conclusion"] == "failure" and result["total"] == 389 and result["passed"] == 386
                    and result["failed"] == 1 and result["skipped"] == 2
                    and [r["test"] for r in failures] == ["test_the_idle_matches_its_golden"]
                    and {r["test"] for r in skips} == {"test_responsive_default_aliases_and_setup_use_identical_walks",
                                                       "test_xbot_rooted_walk_and_run_play_with_contact"}
                    and not result["engine_errors"] and not result["discovery_errors"] and not result["tool_route_errors"]
                    and raw.count("CI_TOOL_ROUTE_PASS: 10 families, 103 operation dry-run routes") == 2,
                    "Unexpected editor failure: " + name)
            item.update(total=result["total"], passed=result["passed"], failed=1, skipped=2,
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
    # CI checks out GitHub's synthetic merge; prove its tracked tree equals source.
    merge = re.findall(r"HEAD is now at ([a-f0-9]+) Merge " + re.escape(args.source), Path(editors[0]["log"]).read_text(encoding="utf-8"))
    require(len(merge) == 1, "Missing tested merge checkout")
    repo_slug = "michaltomczykowski/godot-ai-animation-toolkit"
    tested = json.loads(gh("api", f"repos/{repo_slug}/commits/{merge[0]}"))
    local_tree = subprocess.check_output(["git", "rev-parse", args.source + "^{tree}"], cwd=args.repo, text=True).strip()
    require(tested["commit"]["tree"]["sha"] == local_tree, "CI merge tree differs from source")
    receipt = {"source_head": args.source, "tested_merge": tested["sha"], "tracked_tree_matches_source": True,
               "run_id": args.run_id, "url": run["url"], "status": run["status"], "conclusion": run["conclusion"],
               "expected_legacy_idle_golden_only": True, "all_other_source_jobs_pass": True,
               "headless_jobs": 28, "editor_jobs": editors, "live_mcp_jobs": live,
               "release_ready": False, "archived_utc": datetime.now(timezone.utc).isoformat()}
    write(args.folder / "ci-receipt.json", receipt)
    print("IDLE_SOURCE_CI=28 headless and 2 live pass; 4 editors have only preserved idle golden and private-rig skips")


if __name__ == "__main__":
    main()
