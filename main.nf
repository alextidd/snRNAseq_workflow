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
include { loading     } from './modules/loading'
include { filtering   } from './modules/filtering'
include { merging     } from './modules/merging'
include { integrating } from './modules/integrating'
include { clustering  } from './modules/clustering'
include { annotating  } from './modules/annotating'
include { infercnv    } from './modules/infercnv'

// pipeline workflow
workflow snRNAseq_workflow {
  take:
    ch_filtered
    ch_params
    
  main:
    // dimensionality reduction and clustering
    clustering(
      "${baseDir}/templates/clustering.rmd",
      ch_filtered,
      ch_params
    ) 
    
    // cell type annotation
    annotating(
      "${baseDir}/templates/annotating.rmd",
      clustering.out.ch_clustered,
      ch_params
    )
}

workflow {
  
  // show help message if the user specifies the --help flag at runtime
  // or if any required params are not provided
  if ( params.help || ! params.input.manifest_file || !params.input.sample_metadata_file ) {
      // invoke the function above which prints the help message
      help_message()
      // exit out and do not run anything else
      exit 1
  }
  
  // save params
  save_params()
  
  // initiate ch_run
    Channel
      .empty()
      .set { ch_run }
  
  if ( ! params.preloaded ) {
    
    // generate one channel per id
    Channel
      .fromPath(params.input.manifest_file)
      .splitCsv(header:true, sep:'\t')
      .map { row -> tuple( row.id, row.id_col, row.dir ) }
      .set { ch_ids }
    
    // load each id
    loading(
      ch_ids
    )
    
    // quality control and filtering
    filtering(
      "${baseDir}/templates/filtering.rmd",
      loading.out.ch_loaded,
      save_params.out.ch_params,
    )
    
    if ( params.input.run_all ) {
      // integrate all samples
      filtering.out.ch_filtered
        .map { id, rds_file -> tuple("integrated", "integrated", rds_file) }
        .groupTuple()
        .set { ch_run_all }
        
      // perform integration
      integrating(
        ch_run_all
      )
      
      // add integrated samples to ch_run
      ch_run
        .concat(integrating.out.ch_integrated)
        .set { ch_run }
    }
    
    
    if ( params.input.run_by_patient ) {
      // merge all samples by patient
      filtering.out.ch_filtered
        .map { id, rds_file -> tuple(id.split("_")[0], rds_file) }
        .groupTuple()
        .map { id, rds_file -> tuple(id, "by_patient", rds_file) }
        .set { ch_run_by_patient }
    }
    
    if ( params.input.run_by_patient_wo_organoids ) {
      // merge all samples by patient without organoids
      filtering.out.ch_filtered
        .map { id, rds_file -> tuple(id.split("_")[0].findAll { it.first() =~ "organoid" }, rds_file) }
        .filter { it.first }        
        .groupTuple()
        .map { id, rds_file -> tuple(id, "by_patient_wo_organoids", rds_file) }
        .set { ch_run_by_patient }
      ch_run_by_patient.view()
    }
    
    if ( params.input.run_by_patient | params.input.run_by_patient_wo_organoids ) {
      
      // perform merge
      merging(
        ch_run_by_patient
      )
      
      // add merged samples to ch_run
      ch_run
        .concat(merging.out.ch_merged)
        .set { ch_run }
      
    }
    
    if ( params.input.run_each ) {
      // get each sample
      filtering.out.ch_filtered
        .map { id, rds_file -> tuple(id, "by_sample", rds_file) }
        .set { ch_run_each }
        
      // add each sample to ch_run
      ch_run
        .concat(ch_run_each)
        .set { ch_run }
    }
  
  } else {
    
    // generate runs from preloaded paths
    
    if ( params.input.run_each ) {
      Channel
        .fromPath("${params.output.dir}/by_sample/*/filtering/seu.rds")
        .concat(ch_run)
        .set { ch_run }
    }
    
    if ( params.input.run_by_patient ) {
      Channel
        .fromPath("${params.output.dir}/by_patient/*/merging/seu.rds")
        .concat(ch_run)
        .set { ch_run }
    }
    
    if ( params.input.run_by_patient_wo_organoids) {
      Channel
        .fromPath("${params.output.dir}/by_patient/*/merging/seu.rds")
        .concat(ch_run)
        .set { ch_run }
    }
    
    if ( params.input.run_all ) {
      Channel
        .fromPath("${params.output.dir}/integrated/*/integrating/seu.rds")
        .concat(ch_run)
        .set { ch_run }
    }
    
    ch_run
      .map { file -> tuple(file.toString().tokenize('/')[-3], file.toString().tokenize('/')[-4], file) }
      .set { ch_run }
    ch_run.view()
    
  }
  
  // run on each/all samples/patients
  snRNAseq_workflow(
    ch_run,
    save_params.out.ch_params
  )
  
}


// infercnv - run if reference celltypes or samples provided, on merged output
// TODO: make this work on annotated output for infercnv.reference_samples or
// clustered output for infercnv.reference_celltypes and work on all merged samples
// or all patient samples or annotated individual samples!
//if (  params.infercnv.gene_order_file != false &
//      ((params.infercnv.reference_samples != false) ||
//      (params.infercnv.reference_celltypes != false & params.annotate.annotations_file != false))
//   ) {
//  infercnv(
//    // merged samples will be the first out
//    ch_merged_annotated,
//    "${baseDir}/templates/infercnv.rmd",
//    ch_params
//  )
//}

