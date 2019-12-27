#!/usr/bin/env cwl-runner
#
# Example validate submission file
#
cwlVersion: v1.0
class: CommandLineTool
baseCommand: validate.py

hints:
  DockerRequirement:
    dockerPull: docker.synapse.org/syn18065892/scoring_harness

inputs:

  - id: entity_type
    type: string
  - id: inputfile
    type: File?

arguments:
  - valueFrom: $(inputs.inputfile)
    prefix: --submission_file
  - valueFrom: results.json
    prefix: --results
  - valueFrom: $(inputs.entity_type)
    prefix: --entity_type
  - valueFrom: '/output-schema.json'
    prefix: --schema_filepath

requirements:
  - class: InlineJavascriptRequirement
     
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
