#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python

hints:
  DockerRequirement:
    dockerPull: python:3.7

inputs:
  - id: scores_file
    type: File
  - id: apollo
    type: int
  - id: outcome
    type: int
  - id: rembrandt
    type: int
  - id: roimasks
    type: int

arguments:
  - valueFrom: calc_weighted_score.py
  - valueFrom: $(inputs.scores_file)
    prefix: -s
  - valueFrom: $(inputs.apollo)
    prefix: --apollo
  - valueFrom: $(inputs.outcome)
    prefix: --outcome
  - valueFrom: $(inputs.rembrandt)
    prefix: --rembrandt
  - valueFrom: $(inputs.roimasks)
    prefix: --roi
  - valueFrom: scores.json
    prefix: -r

requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: calc_weighted_score.py
        entry: |
          #!/usr/bin/env python
          import argparse
          import json

          parser = argparse.ArgumentParser()
          parser.add_argument("-s", "--scores", required=True)
          parser.add_argument("-r", "--results", required=True)
          parser.add_argument("--apollo", required=True, type=int)
          parser.add_argument("--outcome", required=True, type=int)
          parser.add_argument("--rembrandt", required=True, type=int)
          parser.add_argument("--roi", required=True, type=int)

          args = parser.parse_args()
          with open(args.scores) as scores, open(args.results, "w") as out:
            results = json.load(scores)
            
            try:
              apo_weight = results.get('APOLLO-2_score') * args.apollo
              out_weight = results.get('Outcome-Predictors_score') * args.outcome
              rem_weight = results.get('REMBRANDT_score') * args.rembrandt
              roi_weight = results.get('ROI-Masks_score') * args.roi
              weighted_avg = sum([apo_weight, out_weight, rem_weight, roi_weight]) / \
                sum([args.apollo, args.outcome, args.rembrandt, args.roi])
              weighted_avg = round(weighted_avg, 3)
            except TypeError:
              weighted_avg = "NA"
            results['weighted_avg'] = weighted_avg
            out.write(json.dumps(results))

outputs:
  - id: results
    type: File
    outputBinding:
      glob: scores.json
