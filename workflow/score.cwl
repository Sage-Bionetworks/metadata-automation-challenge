#!/usr/bin/env cwl-runner
#
# Example score submission file
#
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python

hints:
  DockerRequirement:
    dockerPull: docker.synapse.org/syn18065892/scoring_harness

inputs:
  - id: inputfile
    type: File
  - id: goldstandard
    type: File

arguments:
  - valueFrom: score.py
  - valueFrom: $(inputs.inputfile.path)
  - valueFrom: $(inputs.goldstandard.path)
  - valueFrom: results.json


requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: score.py
        entry: |
          #!/usr/bin/env python
          import argparse
          import json
          parser = argparse.ArgumentParser()
          parser.add_argument("-f", "--submissionfile", required=True, help="Submission File")
          parser.add_argument("-r", "--results", required=True, help="Scoring results")
          parser.add_argument("-g", "--goldstandard", required=True, help="Goldstandard for scoring")

          args = parser.parse_args()
          score = 3
          prediction_file_status = "SCORED"
          result = {'score':score, 'prediction_file_status':prediction_file_status}
          with open(args.results, 'w') as o:
            o.write(json.dumps(result))
     
outputs:
  - id: results
    type: File
    outputBinding:
      glob: results.json