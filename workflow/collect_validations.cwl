#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python

hints:
  DockerRequirement:
    dockerPull: python:3.7

inputs:
  - id: status
    type: string[]
  - id: invalid_reasons
    type: string[]

arguments:
  - valueFrom: merge_validations.py
  - valueFrom: $(inputs.status)
    prefix: -s
  - valueFrom: $(inputs.invalid_reasons)
    prefix: -i
  - valueFrom: results.json
    prefix: -r

requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: merge_validations.py
        entry: |
          #!/usr/bin/env python
          import argparse
          import json

          parser = argparse.ArgumentParser()
          parser.add_argument("-s", "--status", nargs="+", required=True)
          parser.add_argument("-i", "--invalid_reasons", nargs="+", required=True)
          parser.add_argument("-r", "--results", required=True)

          args = parser.parse_args()

          status = "VALIDATED" if all(s == "VALIDATED" for s in args.status) else "INVALID"
          invalid_reasons = "\n".join(args.invalid_reasons)[:500]

          result = {'prediction_file_errors': invalid_reasons,
                    'prediction_file_status': status}

          with open(args.results, "w") as out:
            out.write(json.dumps(result))

outputs:
  - id: results
    type: File
    outputBinding:
      glob: results.json   

  - id: status
    type: string
    outputBinding:
      glob: results.json
      loadContents: true
      outputEval: $(JSON.parse(self[0].contents)['prediction_file_status'])

  - id: invalid_reasons
    type: string
    outputBinding:
      glob: results.json
      loadContents: true
      outputEval: $(JSON.parse(self[0].contents)['prediction_file_errors'])
