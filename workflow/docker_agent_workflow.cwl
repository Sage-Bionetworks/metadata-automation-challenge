#!/usr/bin/env cwl-runner
#
# Sample workflow
# Inputs:
#   submissionId: ID of the Synapse submission to process
#   adminUploadSynId: ID of a folder accessible only to the submission queue administrator
#   submitterUploadSynId: ID of a folder accessible to the submitter
#   workflowSynapseId:  ID of the Synapse entity containing a reference to the workflow file(s)
#
cwlVersion: v1.0
class: Workflow

requirements:
  - class: StepInputExpressionRequirement
  - class: ScatterFeatureRequirement

inputs:
  - id: submissionId
    type: int
  - id: adminUploadSynId
    type: string
  - id: submitterUploadSynId
    type: string
  - id: workflowSynapseId
    type: string
  - id: synapseConfig
    type: File
  - id: dataset
    type: string[]
    default: ['APOLLO-2', 'Outcome-Predictors', 'REMBRANDT', 'ROI-Masks']
    # default: ['Apollo2']


# there are no output at the workflow engine level.  Everything is uploaded to Synapse
outputs: []

steps:
  set_permissions:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/set_permissions.cwl
    in:
      - id: entityid
        source: "#submitterUploadSynId"
      - id: principalid
        valueFrom: "3401978"
      - id: permissions
        valueFrom: "download"
      - id: synapse_config
        source: "#synapseConfig"
    out: []

  get_docker_submission:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/get_submission.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: synapse_config
        source: "#synapseConfig"
    out:
      - id: filepath
      - id: docker_repository
      - id: docker_digest
      - id: entity_id
      - id: entity_type
      - id: results

  get_docker_config:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/get_docker_config.cwl
    in:
      - id: synapse_config
        source: "#synapseConfig"
    out: 
      - id: docker_registry
      - id: docker_authentication

  validate_docker:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/validate_docker.cwl
    in:
      - id: docker_repository
        source: "#get_docker_submission/docker_repository"
      - id: docker_digest
        source: "#get_docker_submission/docker_digest"
      - id: synapse_config
        source: "#synapseConfig"
    out:
      - id: results
      - id: status
      - id: invalid_reasons

  annotate_docker_validation_with_output:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/annotate_submission.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: annotation_values
        source: "#validate_docker/results"
      - id: to_public
        default: true
      - id: force_change_annotation_acl
        default: true
      - id: synapse_config
        source: "#synapseConfig"
    out: [finished]

  run_docker:
    run: run_docker.cwl
    scatter: dataset
    in:
      - id: docker_repository
        source: "#get_docker_submission/docker_repository"
      - id: docker_digest
        source: "#get_docker_submission/docker_digest"
      - id: submissionid
        source: "#submissionId"
      - id: docker_registry
        source: "#get_docker_config/docker_registry"
      - id: docker_authentication
        source: "#get_docker_config/docker_authentication"
      - id: status
        source: "#validate_docker/status"
      - id: parentid
        source: "#submitterUploadSynId"
      - id: synapse_config
        source: "#synapseConfig"
      - id: dataset
        source: "#dataset"
      - id: data_dir
        # Replace this with correct datapath
        valueFrom: "/home/tyu/data"
      - id: docker_script
        default:
          class: File
          location: "run_docker.py"
    out:
      - id: predictions

  upload_results:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/upload_to_synapse.cwl
    scatter: infile
    in:
      - id: infile
        source: "#run_docker/predictions"
      - id: parentid
        source: "#adminUploadSynId"
      - id: used_entity
        source: "#get_docker_submission/entity_id"
      - id: executed_entity
        source: "#workflowSynapseId"
      - id: synapse_config
        source: "#synapseConfig"
    out:
      - id: uploaded_fileid
      - id: uploaded_file_version
      - id: results

  collect_docker:
    run: collect_annotations.cwl
    in:
      - id: files
        source: "#upload_results/results"
    out:
      - id: results

  annotate_docker_upload_results:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/annotate_submission.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: annotation_values
        source: "#collect_docker/results"
      - id: to_public
        default: true
      - id: force_change_annotation_acl
        default: true
      - id: synapse_config
        source: "#synapseConfig"
      - id: previous_annotation_finished
        source: "#annotate_docker_validation_with_output/finished"
    out: [finished]

  validation:
    run: validate.cwl
    scatter: inputfile
    in:
      - id: inputfile
        source: "#run_docker/predictions"
      # Entity type isn't passed in because docker file prediction files are passed
      # From the docker run command
      - id: entity_type
        valueFrom: "none"
    out:
      - id: results
      - id: status
      - id: invalid_reasons
  
  collect_validation:
    run: collect_validations.cwl
    in:
      - id: status
        source: "#validation/status"
      - id: invalid_reasons
        source: "#validation/invalid_reasons"
      - id: parent_id
        source: "#submitterUploadSynId"
      - id: synapse_config
        source: "#synapseConfig"
    out:
      - id: results
      - id: status
      - id: invalid_reasons

  validation_email:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/validate_email.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: synapse_config
        source: "#synapseConfig"
      - id: status
        source: "#collect_validation/status"
      - id: invalid_reasons
        source: "#collect_validation/invalid_reasons"
      - id: errors_only
        default: true
    out: [finished]

  get_goldstandard_id:
    run: get_goldstandard_synid.cwl
    scatter: dataset
    in:
      - id: dataset
        source: "#dataset"
    out:
      - id: synid

  download_goldstandard:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/synapse-client-cwl-tools/v0.1/synapse-get-tool.cwl
    scatter: synapseid
    in:
      - id: synapseid
        source: "#get_goldstandard_id/synid"
      - id: synapse_config
        source: "#synapseConfig"
    out:
      - id: filepath

  annotate_validation_with_output:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/annotate_submission.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: annotation_values
        source: "#collect_validation/results"
      - id: to_public
        default: true
      - id: force_change_annotation_acl
        default: true
      - id: synapse_config
        source: "#synapseConfig"
      - id: previous_annotation_finished
        source: "#annotate_docker_upload_results/finished"
    out: [finished]

  check_status:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/check_status.cwl
    in:
      - id: status
        source: "#collect_validation/status"
      - id: previous_annotation_finished
        source: "#annotate_validation_with_output/finished"
      - id: previous_email_finished
        source: "#validation_email/finished"
    out: [finished]

  scoring:
    run: score.cwl
    scatter: [inputfile, goldstandard, dataset]
    scatterMethod: dotproduct
    in:
      - id: inputfile
        source: "#run_docker/predictions"
      - id: goldstandard
        source: "#download_goldstandard/filepath"
      - id: check_validation_finished
        source: "#check_status/finished"
      - id: dataset
        source: "#dataset"
    out:
      - id: results

  collect_score:
    run: collect_annotations.cwl
    in:
      - id: files
        source: "#scoring/results"
    out:
      - id: results
  
  add_rank:
    run: calc_weighted_score.cwl
    in:
      - id: scores_file
        source: "#collect_score/results"
      - id: apollo
        default: 15
      - id: outcome
        default: 17
      - id: rembrandt
        default: 8
      - id: roimasks
        default: 8
    out:
      - id: results

  score_email:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/score_email.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: synapse_config
        source: "#synapseConfig"
      - id: results
        source: "#add_rank/results"
    out: []

  annotate_submission_with_output:
    run: https://raw.githubusercontent.com/Sage-Bionetworks/ChallengeWorkflowTemplates/v2.2/annotate_submission.cwl
    in:
      - id: submissionid
        source: "#submissionId"
      - id: annotation_values
        source: "#add_rank/results"
      - id: to_public
        default: true
      - id: force_change_annotation_acl
        default: true
      - id: synapse_config
        source: "#synapseConfig"
      - id: previous_annotation_finished
        source: "#annotate_validation_with_output/finished"
    out: [finished]
