#!/usr/bin/env nextflow

// default params set in nextflow.config

// import json function
import java.io.BufferedReader

// using DSL-2
nextflow.enable.dsl=2

log.info """\

snRNAseq workflow
=================
manifest file:        ${params.input.manifest_file}
sample metadata file: ${params.input.sample_metadata_file}
output dir:           ${params.output.dir}
"""

// function which prints help message text
def help_message() {
    log.info"""
usage:

nextflow run <ARGUMENTS>

  (required)

  inputs:
  --input.manifest_file           directory containing sparse matrix of aligned snRNA-seq data
  --input.sample_metadata_file    file containing sample metadata, must contain a 'sample' column

  parallelisation:
  --input.run_each                run the pipeline on each sample
  --input.run_all                 run the pipeline on all samples
  --input.run_by_patient          run the pipeline on each patient (sample IDs must be in the form "patient_*")

  output:
  --output.dir                    optional. output directory, default is './output/'

  filters:
  --filter.do_filtering           logical, default is true
  --filter.n_mads                  integer, number of median absolute deviancies for outlier detection
  --filter.doublets               logical, default is true
  --filter.n_nuclei_per_gene.max  integer or 'adaptive', defailt is 5
  --filter.nCount_RNA.max         integer or 'adaptive', default is 10000
  --filter.nCount_RNA.min         integer or 'adaptive', default is 300
  --filter.nFeature_RNA.max       integer or 'adaptive', default is 10000
  --filter.nFeature_RNA.min       integer or 'adaptive', default is 200
  --filter.percent_mito.max       proportion (0-1) or 'adaptive', default is 0.1

  dimensionality reduction and clustering:
  --n_dims                        integer, number of PCs
  --vars_to_regress               vector of variables to regress out of the SCTransform residuals
  --clustering_resolution         resolution for clustering

  annotating celltypes:
  --annotate.markers_file         file containing markers for celltype annotation, must contain 'gene' and 'population' columns
  --annotate.annotations_file     file containing final celltype annotations for the dataset, must contain an 'annotation' column and a column matching one of the metadata columns (e.g., 'cell', 'cluster' or 'partition') of the object

  infercnv:
  --infercnv.reference_celltypes  comma-delimited list of annotations to use as a reference
  --infercnv.gene_order_file      file containing the positions of each gene along each chromosome in the genome

    """.stripIndent()
}

// import modules
include { save_params } from './modules/save_params'
include { integrating } from './modules/integrating'

workflow {

   Channel
    .fromPath("${params.output.dir}/by_sample/*/filtering/seu.rds")
    .map { file -> tuple(file.toString().tokenize('/')[-3], file) }
    .map { id, rds_file -> tuple(id.split("_")[0], rds_file) }
    .groupTuple()
    .map { id, rds_file -> tuple(id, "by_patient_wo_organoids", rds_file) }
    .set { ch_run }

  // perform integration
  integrating(
    ch_run
  )

}

