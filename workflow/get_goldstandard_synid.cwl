#!/usr/bin/env cwl-runner
#
# Gets the goldstandard synids based on dataset
#
cwlVersion: v1.0
class: ExpressionTool

inputs:
  - id: dataset
    type: string

requirements:
  - class: InlineJavascriptRequirement
     
outputs:
  - id: synid
    type: string

expression: |

  ${
    if (inputs.dataset == "Apollo2"){
      return {synid: "syn21431292"};
    } else if (inputs.dataset == "Outcome-Predictors"){
      return {synid: "syn21431291"};
    } else if (inputs.dataset == "REMBRANDT"){
      return {synid: "syn21431290"};
    } else if (inputs.dataset == "ROI-Masks"){
      return {synid: "syn21431289"};
    } else {
      throw 'no dataset goldstandard';
    }
  }
