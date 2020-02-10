#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python

hints:
  DockerRequirement:
    dockerPull: python:3.7

inputs:
  - id: files
    type: File[]

arguments:
  - valueFrom: merge_annots.py
  - valueFrom: $(inputs.files)
    prefix: -f
  - valueFrom: results.json
    prefix: -r

requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: merge_annots.py
        entry: |
          #!/usr/bin/env python
          import argparse
          import json

          parser = argparse.ArgumentParser()
          parser.add_argument("-f", "--files", nargs="+", required=True)
          parser.add_argument("-r", "--results", required=True)

          args = parser.parse_args()
          results = {}
          for file in args.files:
            with open(file) as f:
              score = json.load(f)
              results.update(score)
          
          with open(args.results, "w") as out:
            out.write(json.dumps(results))

outputs:
  - id: results
    type: File
    outputBinding:
      glob: results.json
