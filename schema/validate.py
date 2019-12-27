#!/usr/bin/env python3
"""Validate input json against json schema"""
import json

import click
from jsonschema import Draft7Validator


def _validate_json(json_filepath, schema_filepath):
    """Validates json with schema

    Args:
        json_filepath: Path to input json
        schema_filepath: Path to schema json

    Returns:
        List of errors, empty if no errors"""
    with open(json_filepath, "r") as json_file:
        data = json.load(json_file)
    with open(schema_filepath, "r") as schema_file:
        schema = json.load(schema_file)
    # Check schema is correct first
    Draft7Validator.check_schema(schema)
    schema_validator = Draft7Validator(schema)
    errors = sorted(schema_validator.iter_errors(data), key=str)
    return errors


@click.command()
@click.option('--submission_file', help='Submission file')
@click.option('--schema_filepath', help='Json schema filepath',
              required=True)
@click.option('--entity_type', help='Submission entity type',
              required=True)
@click.option('--results', help='Results filepath', required=True)
def validate_json_submission(submission_file, schema_filepath, entity_type,
                             results):
    """Validates json submission"""
    invalid_reasons = []
    if submission_file is None:
        prediction_file_status = "INVALID"
        invalid_reasons = ['Expected FileEntity type but found ' + entity_type]
    else:
        errors = _validate_json(submission_file, schema_filepath)
        if errors:
            prediction_file_status = "INVALID"
            invalid_reasons.extend(errors)
        else:
            prediction_file_status = "VALIDATED"

    result = {'prediction_file_errors':"\n".join(invalid_reasons),
              'prediction_file_status':prediction_file_status}
    with open(results, 'w') as out:
        out.write(json.dumps(result))


if __name__ == "__main__":
    validate_json_submission()
