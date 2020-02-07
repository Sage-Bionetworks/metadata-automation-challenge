# metadata-automation-challenge

## Building docker images

```
docker build -t metadata-validation -f Dockerfile.validation .
docker build -t metadata-baseline -f Dockerfile.baseline .
docker build -t metadata-scoring -f Dockerfile.scoring .
```

## Running the baseline method
Here we describe how to apply the baseline method to automatically annotate a dataset (see [Data Description](https://www.synapse.org/#!Synapse:syn18065891/wiki/600449)).

1. Create the folders `input`, `data` and `output` in your current directory.
2. Place the input dataset in `input`, e.g. `input/APOLLO-2.tsv`
3. Run the following command

```
docker run \
  -v $(pwd)/input:/input:ro \
  -v $(pwd)/data:/data:ro \
  -v $(pwd)/output:/output \
  metadata-baseline APOLLO-2
```

where `APOLLO-2` is the name of the dataset in the folder `input` (without the extension `.tsv`). Here `$(pwd)` is automatically replaced to the absolute path of the current directory.

The file `/output/APOLLO-2-Submission.json` is created upon successful completion of the above command.

## Validating the submission file
The following command checks that the format of the submission file generated is valid.

```
$ docker run \
  -v $(pwd)/output/APOLLO-2-Submission.json:/input.json:ro \
  metadata-validation \
  validate-submission --json_filepath /input.json
Your JSON file is valid!
```

where `$(pwd)/output/APOLLO-2-Submission.json` points to the location of the submission file generated in the previous section.

Alternatively, the scoring script can be run directly using Python.

```
$ python3 -m venv venv
$ pip install click jsonschema
```

Here is the generic command to validate the format of a submission file.

```
$ python schema/validate.py validate-submission \
  --json_filepath yourjson.json \
  --schema_filepath schema/output-schema.json
```

To validate the submission file generate in the previous section, the command becomes:

```
$ python schema/validate.py validate-submission \
  --json_filepath output/APOLLO-2-Submission.json \
  --schema_filepath schema/output-schema.json
Your JSON file is valid!
```

## Scoring the submission
Here we evaluate the performance of the submission by comparing the content of the submission file to a gold standard (e.g. manual annotations).

```
$ docker run \
  -v $(pwd)/output/APOLLO-2-Submission.json:/submission.json:ro \
  -v $(pwd)/data/Annotated-APOLLO-2.json:/goldstandard.json:ro \
  -v $(pwd)/output:/output \
  metadata-scoring APOLLO-2
── Attaching packages ─────────────────────────────────────── tidyverse 1.3.0 ──
✔ ggplot2 3.2.1     ✔ purrr   0.3.3
✔ tibble  2.1.3     ✔ dplyr   0.8.3
✔ tidyr   1.0.2     ✔ stringr 1.4.0
✔ readr   1.3.1     ✔ forcats 0.4.0
── Conflicts ────────────────────────────────────────── tidyverse_conflicts() ──
✖ dplyr::filter() masks stats::filter()
✖ dplyr::lag()    masks stats::lag()
Scoring annotation submitted for 'APOLLO-2' dataset

$ cat output/score.json
{
  "APOLLO-2_score": 0.9692,
  "prediction_file_status": "SCORED"
}
```