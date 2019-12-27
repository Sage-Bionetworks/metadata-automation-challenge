# metadata-automation-challenge


## Running the Validator

Using Python:
* Python > 3.6
* `pip install click jsonschema`

```
python schema/validate.py validate-input --json_filepath yourjson.json --schema_filepath schema/output-schema.json
```

If you do not have python environments set up, please install docker and run this command:

```
docker run -v /full/path/to/your/json/yourjson.json:/input.json docker.synapse.org/syn18065892/scoring_harness validate.py validate-input --json_filepath /input.json
```