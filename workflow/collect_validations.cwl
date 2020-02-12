#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python3

hints:
  DockerRequirement:
    dockerPull: sagebionetworks/synapsepythonclient:v1.9.2

inputs:
  - id: status
    type: string[]
  - id: invalid_reasons
    type: string[]
  - id: parent_id
    type: string
  - id: synapse_config
    type: File

arguments:
  - valueFrom: merge_validations.py
  - valueFrom: $(inputs.status)
    prefix: -s
  - valueFrom: $(inputs.invalid_reasons)
    prefix: -i
  - valueFrom: results.json
    prefix: -r
  - valueFrom: $(inputs.parent_id)
    prefix: -p
  - valueFrom: $(inputs.synapse_config.path)
    prefix: -c

requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: merge_validations.py
        entry: |
          #!/usr/bin/env python
          import argparse
          import json
          import synapseclient

          parser = argparse.ArgumentParser()
          parser.add_argument("-s", "--status", nargs="+", required=True)
          parser.add_argument("-i", "--invalid_reasons", nargs="+", required=True)
          parser.add_argument("-r", "--results", required=True)
          parser.add_argument("-p", "--parent_id", required=True)
          parser.add_argument("-c", "--config", required=True)

          args = parser.parse_args()

          status = "VALIDATED" if all(s == "VALIDATED" for s in args.status) else "INVALID"
          message = ""

          invalid_reasons = "\n".join(args.invalid_reasons)
          if status == "INVALID":
            log_file = "validation_errors.txt"
            with open(log_file, 'w') as log:
              log.write(invalid_reasons)
            syn = synapseclient.Synapse(configPath=args.config)
            syn.login()
            ent = synapseclient.File(log_file, parent=args.parent_id)
            ent = syn.store(ent)
            message = "Errors found. For more details, review the validations log file of this submission (https://www.synapse.org/#!Synapse:{}).".format(ent.id)

          result = {'prediction_file_errors': message,
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
