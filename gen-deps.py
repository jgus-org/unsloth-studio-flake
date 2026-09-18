import argparse
import importlib.util
import json
import os
from dataclasses import dataclass
from pathlib import Path

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


def load_deps_core():
    spec = importlib.util.spec_from_file_location("deps_core", os.environ["DEPS_CORE"])
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


deps_core = load_deps_core()

BUILD_MARKER_ENVIRONMENT = {"sys_platform": "linux"}


@dataclass(frozen=True, order=True)
class RequirementRecord:
    name: str
    requirement: str
    marker_json: str


def parse_requirement(value: str) -> RequirementRecord:
    requirement = Requirement(value)
    applicable = deps_core.applicability(
        str(requirement.marker) if requirement.marker is not None else None,
        BUILD_MARKER_ENVIRONMENT,
    )
    return RequirementRecord(
        name=canonicalize_name(requirement.name),
        requirement=str(requirement),
        marker_json=json.dumps(deps_core.to_jsonable(applicable), sort_keys=True),
    )


def parse_pyproject(path: Path) -> set[RequirementRecord]:
    document = path.read_text(encoding="utf-8")
    return {
        parse_requirement(value)
        for value in deps_core.pyproject_requirements(
            document, ["studio", "huggingfacenotorch"]
        )
    }


def parse_requirements_file(path: Path) -> set[RequirementRecord]:
    text = path.read_text(encoding="utf-8")
    return {parse_requirement(value) for value in deps_core.requirements_file_requirements(text)}


def nix_string(value: str) -> str:
    return json.dumps(value)


def render_marker(marker_json: str) -> str:
    def render(marker) -> str:
        if marker is True:
            return "null"
        if marker is False:
            return "false"
        kind = marker["kind"]
        if kind == "cmp":
            return (
                "{ kind = \"cmp\"; "
                f"variable = {nix_string(marker['variable'])}; "
                f"operator = {nix_string(marker['operator'])}; "
                f"literal = {nix_string(marker['literal'])}; "
                "}"
            )
        children = " ".join(render(child) for child in marker["conditions"])
        return f"({kind} [ {children} ])"

    return render(json.loads(marker_json))


def render_requirement(requirement: RequirementRecord) -> str:
    return (
        "  { "
        f"name = {nix_string(requirement.name)}; "
        f"requirement = {nix_string(requirement.requirement)}; "
        f"marker = {render_marker(requirement.marker_json)}; "
        "}"
    )


def generate(source: Path) -> list[RequirementRecord]:
    requirements = parse_pyproject(source / "pyproject.toml")
    requirements.update(
        parse_requirements_file(
            source / "studio" / "backend" / "requirements" / "studio.txt"
        )
    )
    requirements.update(
        parse_requirements_file(
            source / "studio" / "backend" / "requirements" / "base.txt"
        )
    )
    if not requirements:
        raise ValueError("parsed zero runtime requirements from upstream")
    return sorted(requirements)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    requirements = generate(args.source)
    body = "\n".join(render_requirement(requirement) for requirement in requirements)
    args.output.write_text(f"[\n{body}\n]\n", encoding="utf-8")
    print(f"  wrote {len(requirements)} requirements to {args.output}")


if __name__ == "__main__":
    main()
