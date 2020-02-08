#!/usr/bin/env python3
"""Validate input json against json schema"""
import json
import itertools
import os

import click
from jsonschema import Draft7Validator


@click.group()
def cli():
    """Validation of input for participants and CWL tool"""


def _validate_json(json_filepath, schema_filepath):
    """Validates json with schema

    Args:
        json_filepath: Path to input json
        schema_filepath: Path to schema json

    Returns:
        List of errors, empty if no errors"""
    try:
        with open(json_filepath, "r") as json_file:
            data = json.load(json_file)
    except json.decoder.JSONDecodeError:
        errors = ['Submission is not a valid JSON file']
        return errors
    with open(schema_filepath, "r") as schema_file:
        schema = json.load(schema_file)
    # Check schema is correct first
    Draft7Validator.check_schema(schema)
    schema_validator = Draft7Validator(schema)
    # Extract error messages
    errors = [f'Error: {error.message}\n  at {_parse_path(error.absolute_path)}'
              #(error.message, error.absolute_path)
              for error in schema_validator.iter_errors(data)]
    return errors


def _grouper(n, iterable, fillvalue=None):
    "grouper(3, 'ABCDEFG', 'x') --> ABC DEF Gxx"
    args = [iter(iterable)] * n
    return itertools.zip_longest(*args, fillvalue=fillvalue)


def _parse_path(error_path):
    path_parts = []
    for field_loc in _grouper(2, error_path):
        field, loc = field_loc
        if type(loc) == str:
            loc = f'"{loc}""'
        path_parts.append(f'{field}[{loc}]')
    return '::'.join(path_parts)


@cli.command()
@click.option('--json_filepath', help='Submission file',
              type=click.Path(exists=True))
@click.option('--schema_filepath', help='Json schema filepath',
              default="/output-schema.json", type=click.Path(exists=True))
def validate_submission(json_filepath, schema_filepath):
    """Validates submission"""
    errors = _validate_json(json_filepath, schema_filepath)
    if errors:
        for error in errors:
            print(error)
    else:
        print("Your JSON file is valid!")


@cli.command()
@click.option('--submission_file', help='Submission file')
@click.option('--schema_filepath', help='Json schema filepath',
              required=True)
@click.option('--entity_type', help='Submission entity type',
              required=True)
@click.option('--results', help='Results filepath', required=True)
def validate_submission_tool(submission_file, schema_filepath,
                             entity_type, results):
    """Validates submission: used by cwltool"""
    invalid_reasons = []
    if submission_file is None:
        prediction_file_status = "INVALID"
        invalid_reasons = ['Expected FileEntity type but found ' + entity_type]
        dataset = ''
    else:
        errors = _validate_json(submission_file, schema_filepath)
        if errors:
            prediction_file_status = "INVALID"
            invalid_reasons.extend(errors)
        else:
            prediction_file_status = "VALIDATED"
        dataset = os.path.basename(submission_file).replace("-Submission.json", '')
    if invalid_reasons:
        error_string = '{}: {}'.format(dataset,
                                       "\n".join(invalid_reasons)[:500])
    else:
        error_string = ''
    result = {'prediction_file_errors': error_string,
              'prediction_file_status': prediction_file_status}
    with open(results, 'w') as out:
        out.write(json.dumps(result))


if __name__ == "__main__":
    cli()
