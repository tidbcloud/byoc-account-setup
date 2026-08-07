#!/usr/bin/env python3
"""Validate IAM policy document sizes in the CloudFormation templates.

The IAM size limits exclude whitespace. This tool renders CloudFormation
intrinsics with representative parameter values, then measures compact JSON
for every inline and customer-managed policy in each template.
"""

import argparse
import json
import re
import sys
from pathlib import Path

import yaml


INLINE_POLICY_LIMIT = 10_240
MANAGED_POLICY_LIMIT = 6_144
NO_VALUE = object()
PSEUDO_PARAMETERS = {
    "AWS::AccountId": "123456789012",
    "AWS::Partition": "aws",
}


class CloudFormationLoader(yaml.SafeLoader):
    """Parse CloudFormation shorthand tags into their long-form mappings."""


def construct_intrinsic(loader, suffix, node):
    names = {
        "Equals": "Fn::Equals",
        "If": "Fn::If",
        "Join": "Fn::Join",
        "Not": "Fn::Not",
        "Sub": "Fn::Sub",
    }
    if isinstance(node, yaml.ScalarNode):
        value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node)
    else:
        value = loader.construct_mapping(node)
    return {names.get(suffix, suffix): value}


CloudFormationLoader.add_multi_constructor("!", construct_intrinsic)


def parameter_values(template, overrides):
    values = dict(PSEUDO_PARAMETERS)
    for name, definition in template.get("Parameters", {}).items():
        value = overrides.get(name, definition.get("Default"))
        if value is None:
            # Required values only affect ARN lengths in this template.
            value = "Z123456789012345678901234567890"
        if definition.get("Type") == "CommaDelimitedList":
            values[name] = [] if value == "" else str(value).split(",")
        else:
            values[name] = str(value)
    return values


def render(value, parameters, conditions):
    if isinstance(value, list):
        return [item for item in (render(item, parameters, conditions) for item in value) if item is not NO_VALUE]
    if not isinstance(value, dict):
        return value

    if len(value) == 1:
        name, argument = next(iter(value.items()))
        if name == "Ref":
            if argument == "AWS::NoValue":
                return NO_VALUE
            # Resource references are relevant to surrounding role properties,
            # but not to the IAM policy document size being measured.
            return parameters.get(argument, f"resource:{argument}")
        if name == "Fn::Equals":
            left, right = render(argument, parameters, conditions)
            return left == right
        if name == "Fn::Not":
            return not render(argument, parameters, conditions)[0]
        if name == "Fn::Join":
            separator, items = render(argument, parameters, conditions)
            return separator.join(items)
        if name == "Fn::If":
            condition, true_value, false_value = argument
            selected = true_value if conditions[condition] else false_value
            return render(selected, parameters, conditions)
        if name == "Fn::Sub":
            if isinstance(argument, str):
                body, scope = argument, parameters
            else:
                body = argument[0]
                scope = {**parameters, **render(argument[1], parameters, conditions)}

            def replacement(match):
                key = match.group(1)
                if key in scope:
                    return str(scope[key])
                # A pseudo parameter that is not in scope is a typo; anything
                # else is a resource reference, which the Ref branch above also
                # treats as irrelevant to the document size being measured.
                if key.startswith("AWS::"):
                    raise KeyError(f"unsupported pseudo parameter {key!r} in Fn::Sub {body!r}")
                return f"resource:{key}"

            return re.sub(r"\$\{([^}]+)\}", replacement, body)

    return {
        key: rendered
        for key, item in value.items()
        if (rendered := render(item, parameters, conditions)) is not NO_VALUE
    }


def document_size(document):
    return len(json.dumps(document, separators=(",", ":"), ensure_ascii=True))


def check_template(path, template, overrides):
    parameters = parameter_values(template, overrides)
    conditions = {
        name: render(expression, parameters, {})
        for name, expression in template.get("Conditions", {}).items()
    }

    failures = []
    print(f"{path}:")
    for logical_id, resource in template.get("Resources", {}).items():
        properties = render(resource.get("Properties", {}), parameters, conditions)
        if resource.get("Type") == "AWS::IAM::ManagedPolicy":
            size = document_size(properties["PolicyDocument"])
            print(f"  {logical_id}: managed policy {size}/{MANAGED_POLICY_LIMIT} characters")
            if size > MANAGED_POLICY_LIMIT:
                failures.append(f"{path}: {logical_id} exceeds the managed-policy limit")
        elif resource.get("Type") == "AWS::IAM::Role":
            policies = properties.get("Policies", [])
            total = sum(document_size(policy["PolicyDocument"]) for policy in policies)
            if policies:
                print(f"  {logical_id}: inline policies {total}/{INLINE_POLICY_LIMIT} characters")
            if total > INLINE_POLICY_LIMIT:
                failures.append(f"{path}: {logical_id} exceeds the inline-policy aggregate limit")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "templates",
        nargs="*",
        type=Path,
        help="CloudFormation templates to inspect (defaults to every template beside this script)",
    )
    parser.add_argument(
        "--parameter",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="Override a template parameter while calculating policy sizes",
    )
    args = parser.parse_args()

    templates = args.templates or sorted(Path(__file__).resolve().parent.glob("*.yaml"))
    if not templates:
        parser.error("no templates to inspect")

    overrides = {}
    for parameter in args.parameter:
        name, separator, value = parameter.partition("=")
        if not separator or not name:
            parser.error(f"invalid parameter override: {parameter!r}")
        overrides[name] = value

    loaded = [(path, yaml.load(path.read_text(), Loader=CloudFormationLoader)) for path in templates]
    # A misspelled override would otherwise be ignored, leaving the run passing
    # without ever measuring the case it was meant to cover.
    declared = {name for _, template in loaded for name in template.get("Parameters", {})}
    unknown = sorted(set(overrides) - declared)
    if unknown:
        parser.error(f"no inspected template declares parameter(s): {', '.join(unknown)}")

    failures = []
    for path, template in loaded:
        failures.extend(check_template(path, template, overrides))

    if failures:
        print("ERROR: " + "; ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
