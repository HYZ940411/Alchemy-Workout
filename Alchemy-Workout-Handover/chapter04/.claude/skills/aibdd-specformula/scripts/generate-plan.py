# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Generate specformula plan from asset templates.

Usage:
    uv run generate-plan.py --slug <slug> --summary <summary> [--project-root <path>]

Reads specs/arguments.yml, resolves template variables, and writes
plans/<slug>/plan.md + plans/<slug>/todo/01~08.md in one shot.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path
from string import Template

import yaml


def detect_tech_stack(args_data: dict) -> tuple[str, str]:
    """Detect LANG and TEST_STRATEGY from arguments.yml keys."""
    keys = set(args_data.keys())
    if any(k.startswith("PY_") for k in keys):
        lang = "python"
        strategy = "e2e"
        if any(k.startswith("PY_") and "UT" in k for k in keys):
            strategy = "ut"
    elif any(k.startswith("JAVA_") for k in keys):
        lang = "java"
        strategy = "e2e"
    elif any(k.startswith("TS_") for k in keys):
        lang = "typescript"
        strategy = "e2e"
    elif any(k.startswith("SRC_DIR") for k in keys):
        lang = "frontend"
        strategy = "frontend-only"
    else:
        lang = "unknown"
        strategy = "unknown"
    return lang, strategy


def resolve_variables(args_data: dict, slug: str, summary: str, project_root: Path) -> dict:
    """Build the full variable dict for template substitution."""
    specs_root = args_data.get("SPECS_ROOT_DIR", "specs")
    lang, strategy = detect_tech_stack(args_data)

    return {
        "REQUIREMENT_TITLE": slug,
        "REQUIREMENT_SUMMARY": summary,
        "DATE": date.today().isoformat(),
        "PLAN_DIR": f"plans/{slug}",
        "SPECS_ROOT_DIR": specs_root,
        "FEATURES_DIR": f"{specs_root}/features",
        "PROJECT_ROOT": str(project_root),
        "LANG": lang,
        "TEST_STRATEGY": strategy,
        "PORT": "8000",
    }


def safe_substitute(template_text: str, variables: dict) -> str:
    """Substitute ${VAR} patterns, leaving unknown ones intact."""
    # string.Template uses $VAR or ${VAR}. We want to leave unknown vars.
    return Template(template_text).safe_substitute(variables)


def main():
    parser = argparse.ArgumentParser(description="Generate specformula plan from templates")
    parser.add_argument("--slug", required=True, help="Plan slug (e.g. 猜數字遊戲)")
    parser.add_argument("--summary", required=True, help="Requirement summary (1-2 sentences)")
    parser.add_argument("--project-root", default=".", help="Project root path (default: .)")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    arguments_yml = project_root / "specs" / "arguments.yml"

    if not arguments_yml.exists():
        print(f"Error: {arguments_yml} not found. Run /aibdd-kickoff first.", file=sys.stderr)
        sys.exit(1)

    with open(arguments_yml) as f:
        args_data = yaml.safe_load(f) or {}

    variables = resolve_variables(args_data, args.slug, args.summary, project_root)

    # Locate asset templates (sibling directory)
    script_dir = Path(__file__).resolve().parent
    assets_dir = script_dir.parent / "assets"

    if not assets_dir.exists():
        print(f"Error: assets directory not found at {assets_dir}", file=sys.stderr)
        sys.exit(1)

    # Create plan directory structure
    plan_dir = project_root / "plans" / args.slug
    todo_dir = plan_dir / "todo"
    doing_dir = plan_dir / "doing"
    done_dir = plan_dir / "done"

    for d in [todo_dir, doing_dir, done_dir]:
        d.mkdir(parents=True, exist_ok=True)

    # Generate plan.md
    plan_template = assets_dir / "plan-template.md"
    if plan_template.exists():
        content = safe_substitute(plan_template.read_text(encoding="utf-8"), variables)
        (plan_dir / "plan.md").write_text(content, encoding="utf-8")
        print(f"  plan.md")

    # Generate phase cards (01~08)
    card_templates = sorted(assets_dir.glob("[0-9][0-9]-*.md"))
    for template_path in card_templates:
        content = safe_substitute(template_path.read_text(encoding="utf-8"), variables)
        output_path = todo_dir / template_path.name
        output_path.write_text(content, encoding="utf-8")
        print(f"  todo/{template_path.name}")

    print(f"\nPlan generated: {plan_dir}")
    print(f"  {1 + len(card_templates)} files written")


if __name__ == "__main__":
    main()
