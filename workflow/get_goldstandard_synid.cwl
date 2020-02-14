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
    if (inputs.dataset == "APOLLO-2"){
      return {synid: "syn21595885"};
    } else if (inputs.dataset == "Outcome-Predictors"){
      return {synid: "syn21595889"};
    } else if (inputs.dataset == "REMBRANDT"){
      return {synid: "syn21595894"};
    } else if (inputs.dataset == "ROI-Masks"){
      return {synid: "syn21595898"};
    } else {
      throw 'no dataset goldstandard';
    }
  }
