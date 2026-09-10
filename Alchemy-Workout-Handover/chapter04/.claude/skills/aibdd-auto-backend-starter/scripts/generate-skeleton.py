# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Generate Python E2E project skeleton from templates.

Usage:
    uv run generate-skeleton.py --project-dir <path> --project-name <name>

Reads specs/arguments.yml, resolves template variables, and writes
the full project skeleton in one shot.
"""

import argparse
import re
import sys
from pathlib import Path
from string import Template

import yaml


def slugify(name: str) -> str:
    """Convert project name to URL-safe slug."""
    slug = name.lower().strip()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_]+", "-", slug)
    slug = re.sub(r"-+", "-", slug)
    return slug.strip("-")


def resolve_args_variables(args_data: dict) -> dict:
    """Resolve ${VAR} references within arguments.yml values."""
    resolved = {}
    for key, value in args_data.items():
        if isinstance(value, str):
            # Iteratively resolve ${VAR} references
            prev = None
            current = value
            while current != prev:
                prev = current
                current = Template(current).safe_substitute(resolved)
            resolved[key] = current
        else:
            resolved[key] = value
    return resolved


def build_variables(args_data: dict, project_name: str, project_dir: Path) -> dict:
    """Build the full variable dict for template substitution."""
    resolved = resolve_args_variables(args_data)
    slug = slugify(project_name)
    py_app_dir = resolved.get("PY_APP_DIR", "app")
    py_app_module = py_app_dir.replace("/", ".")
    py_test_features_dir = resolved.get("PY_TEST_FEATURES_DIR", "tests/features")
    py_test_module = py_test_features_dir.replace("/", ".")

    variables = {
        **resolved,
        "PROJECT_NAME": project_name,
        "PROJECT_SLUG": slug,
        "PROJECT_DESCRIPTION": f"{project_name} — BDD Workshop Python E2E",
        "PY_APP_MODULE": py_app_module,
        "PY_TEST_MODULE": py_test_module,
        "DB_NAME": slug.replace("-", "_") + "_dev",
    }
    return variables


def write_template(template_path: Path, output_path: Path, variables: dict) -> None:
    """Read template, substitute variables, write output."""
    content = template_path.read_text(encoding="utf-8")
    result = Template(content).safe_substitute(variables)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        print(f"  SKIP (exists): {output_path}")
        return
    output_path.write_text(result, encoding="utf-8")
    print(f"  {output_path.relative_to(output_path.parent.parent.parent) if len(output_path.parts) > 3 else output_path.name}")


def template_name_to_path(name: str) -> str:
    """Convert template filename (__ = /) to output path. Strip .tmpl suffix."""
    # Protect Python's __init__ before replacing __ with /
    name = name.replace("__init__", "\x00INIT\x00")
    path = name.replace("__", "/")
    path = path.replace("\x00INIT\x00", "__init__")
    if path.endswith(".tmpl"):
        path = path[:-5]
    return path


def create_empty_inits(project_dir: Path, variables: dict) -> None:
    """Create empty __init__.py files for packages that don't have templates."""
    py_app_dir = variables.get("PY_APP_DIR", "app")
    dirs_needing_init = [
        f"{py_app_dir}/repositories",
        f"{py_app_dir}/services",
        f"{py_app_dir}/schemas",
    ]
    for d in dirs_needing_init:
        init_path = project_dir / d / "__init__.py"
        if not init_path.exists():
            init_path.parent.mkdir(parents=True, exist_ok=True)
            init_path.write_text("", encoding="utf-8")
            print(f"  {d}/__init__.py (empty)")


def main():
    parser = argparse.ArgumentParser(description="Generate Python E2E project skeleton")
    parser.add_argument("--project-dir", required=True, help="Backend project root directory")
    parser.add_argument("--project-name", required=True, help="Project display name")
    parser.add_argument("--variant", default="python-e2e", help="Template variant (default: python-e2e)")
    parser.add_argument("--arguments", required=True, help="Path to arguments.yml")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    arguments_yml = Path(args.arguments).resolve()

    if not arguments_yml.exists():
        print(f"Error: {arguments_yml} not found. Run /aibdd-kickoff first.", file=sys.stderr)
        sys.exit(1)

    with open(arguments_yml) as f:
        args_data = yaml.safe_load(f) or {}

    variables = build_variables(args_data, args.project_name, project_dir)

    # Locate templates
    script_dir = Path(__file__).resolve().parent
    templates_dir = script_dir.parent / "templates" / args.variant

    if not templates_dir.exists():
        print(f"Error: templates directory not found at {templates_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Generating skeleton in: {project_dir}")
    print(f"  variant: {args.variant}")
    print(f"  project: {args.project_name} ({variables['PROJECT_SLUG']})")
    print()

    # Process each template file
    count = 0
    for template_path in sorted(templates_dir.iterdir()):
        if template_path.is_file():
            output_rel = template_name_to_path(template_path.name)
            output_path = project_dir / output_rel
            write_template(template_path, output_path, variables)
            count += 1

    # Create empty __init__.py files
    create_empty_inits(project_dir, variables)

    # Create alembic/versions/ directory
    versions_dir = project_dir / variables.get("ALEMBIC_VERSIONS_DIR", "alembic/versions")
    versions_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nSkeleton generated: {count} files written")


if __name__ == "__main__":
    main()
