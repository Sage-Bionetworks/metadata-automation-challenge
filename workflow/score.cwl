#!/usr/bin/env cwl-runner
#
# Example score submission file
#
cwlVersion: v1.0
class: CommandLineTool
baseCommand: score-submission-tool

hints:
  DockerRequirement:
    dockerPull: docker.synapse.org/syn18065892/scoring

inputs:
  - id: inputfile
    type: File
  - id: goldstandard
    type: File
  - id: dataset
    type: string
  - id: check_validation_finished
    type: boolean?

arguments:
  - valueFrom: $(inputs.inputfile.path)
  - valueFrom: $(inputs.goldstandard.path)
  - valueFrom: results.json
  - valueFrom: $(inputs.dataset)

requirements:
  - class: InlineJavascriptRequirement
     
outputs:
  - id: results
    type: File
    outputBinding:
      glob: results.json