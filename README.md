# Metadata Automation Challenge

## Using the baseline demo in RStudio

### Environment setup

1. Clone this repository

2. Open `metadata-automation-challenge.Rproj`

3. Install packages. In the RStudio console, run:

```
renv::restore()
```

This may take some time to complete - get something nice to drink :)

4. Create the folders `input`, `data` and `output` in your current directory.

5. Create `.synapseConfig` file

See this vignette about [Managing Synapse Credentials](https://r-docs.synapse.org/articles/manageSynapseCredentials.html) to learn how to store credentials to login without needing to specify your username and password each time. 

### Open and run the demo notebook

You can find the baseline demo R Notebook at `baseline_demo/baseline_demo.Rmd`. After opening the notebook, you should be able to step through and execute each chunk in order.

## Building Docker images

```
docker build -t metadata-baseline -f Dockerfile.baseline .
docker build -t metadata-validation -f Dockerfile.validation .
docker build -t metadata-scoring -f Dockerfile.scoring .
```

## Running the baseline method with Docker

Here we describe how to apply the baseline method to automatically annotate a dataset (see [Data Description](https://www.synapse.org/#!Synapse:syn18065891/wiki/600449)).

1. Create the folders `input`, `data` and `output` in your current directory.
2. Place the input dataset in `input`, e.g. `input/APOLLO-2-leaderboard.tsv`
3. Run the following command

```
docker run \
  -v $(pwd)/input:/input:ro \
  -v $(pwd)/data:/data:ro \
  -v $(pwd)/output:/output \
  metadata-baseline APOLLO-2-leaderboard
```

where `APOLLO-2` is the name of the dataset in the folder `input` (without the extension `.tsv`). Here `$(pwd)` is automatically replaced to the absolute path of the current directory.

The file `/output/APOLLO-2-leaderboard-Submission.json` is created upon successful completion of the above command.

## Validating the submission file

The following command checks that the format of the submission file generated is valid.

```
$ docker run \
  -v $(pwd)/output/APOLLO-2-leaderboard-Submission.json:/input.json:ro \
  metadata-validation \
  validate-submission --json_filepath /input.json
Your JSON file is valid!
```

where `$(pwd)/output/APOLLO-2-leaderboard-Submission.json` points to the location of the submission file generated in the previous section.

Alternatively, the validation script can be run directly using Python.

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

To validate the submission file generated in the previous section, the command becomes:

```
$ python schema/validate.py validate-submission \
  --json_filepath output/APOLLO-2-leaderboard-Submission.json \
  --schema_filepath schema/output-schema.json
Your JSON file is valid!
```

## Scoring the submission

Here we evaluate the performance of the submission by comparing the content of the submission file to a gold standard (e.g. manual annotations).

```
$ docker run \
  -v $(pwd)/output/APOLLO-2-leaderboard-Submission.json:/submission.json:ro \
  -v $(pwd)/data/Annotated-APOLLO-2-leaderboard.json:/goldstandard.json:ro \
  metadata-scoring score-submission /submission.json /goldstandard.json
1.24839015151515
```
