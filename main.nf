include { PARSE_SAMPLESHEET               } from './subworkflows/parse_samplesheet'
include { VALIDATE_PARAMETERS             } from './subworkflows/parameter_validation'
include { VARIANTMEDIUM_PREPARE_INPUTS    } from './workflows/variantmedium_prepare_inputs'
include { VARIANTMEDIUM_STAGE_DATA        } from './workflows/variantmedium_stage_data'
include { BAM_PREPROCESSING               } from './modules/external/bam_preprocessing/main'
include { CANDIDATE_CALLING               } from './modules/external/candidate_calling/main'
include { FEATURE_GENERATION              } from './modules/external/feature_generation/main'
include { VARIANTMEDIUM_FILTER_CANDIDATES } from './workflows/variantmedium_filter_candidates'
include { TENSOR_GENERATION               } from './modules/external/tensor_generation/main'
include { VARIANTMEDIUM_CALL_VARIANTS     } from './workflows/variantmedium_call_variants'

workflow {

    VALIDATE_PARAMETERS()

    def samplesheetFile = file(params.samplesheet)
    if (!samplesheetFile.exists()) {
        error "Samplesheet does not exist: ${params.samplesheet}"
    }
    ch_samplesheet = channel.fromPath(params.samplesheet)
    PARSE_SAMPLESHEET(ch_samplesheet)

    // resolve reference paths — from data staging outputs or user-supplied overrides
    def ref         = params.ref         ?: "${params.outdir}/data_staging/ref_data/GRCh38.d1.vd1.fa"
    def exome_bed   = params.exome_bed   ?: "${params.outdir}/data_staging/ref_data/S07604624_Covered_human_all_v6_plus_UTR.liftover.to.hg38.sorted.bed.gz"
    def dbsnp       = params.dbsnp       ?: "${params.outdir}/data_staging/ref_data/dbsnp_146.hg38.vcf.gz"
    def known_indels1 = params.known_indels1 ?: "${params.outdir}/data_staging/ref_data/ALL.wgs.1000G_phase3.GRCh38.ncbi_remapper.20150424.shapeit2_indels.vcf.gz"

    // step 1: generate input TSVs
    VARIANTMEDIUM_PREPARE_INPUTS(ch_samplesheet, params.outdir)
    ch_tsv_folder = VARIANTMEDIUM_PREPARE_INPUTS.out.tsv_folder

    // step 2: stage reference data and models
    if (params.run_data_staging) {
        VARIANTMEDIUM_STAGE_DATA()
    }

    // step 3: BAM preprocessing
    BAM_PREPROCESSING(
        ch_tsv_folder.map { it.find { f -> f.name == 'preproc.tsv' } },
        ref,
        exome_bed,
        dbsnp,
        known_indels1,
        params.outdir
    )

    // resolve preprocessed BAM dir — skip path or pipeline output
    ch_bam_dir = params.skip_preprocessing
        ? channel.fromPath("${params.outdir}/output_01_01_preprocessed_bams", checkIfExists: true)
        : BAM_PREPROCESSING.out.bam_dir

    // step 4: candidate calling (Strelka2)
    CANDIDATE_CALLING(
        ch_tsv_folder.map { it.find { f -> f.name == 'pairs_wo_reps.tsv' } },
        ref,
        exome_bed,
        params.outdir
    )

    ch_vcf_dir = params.skip_candidate_calling
        ? channel.fromPath("${params.outdir}/output_01_02_candidates_strelka2", checkIfExists: true)
        : CANDIDATE_CALLING.out.vcf_dir

    // step 5: feature generation (VCF postprocessing)
    FEATURE_GENERATION(
        ch_tsv_folder.map { it.find { f -> f.name == 'vcfs.tsv' } },
        ch_tsv_folder.map { it.find { f -> f.name == 'bams.tsv' } },
        ref,
        params.outdir
    )

    ch_features_dir = params.skip_feature_generation
        ? channel.fromPath("${params.outdir}/output_01_03_vcf_postprocessing", checkIfExists: true)
        : FEATURE_GENERATION.out.features_dir

    // step 6: ExtraTrees candidate filtering
    ch_samples_w_cands = ch_features_dir.map {
        file("${params.outdir}/${params.prepare_tsv_outs}/samples_w_cands.tsv")
    }
    ch_outdir_filter = "${params.outdir}/${params.candidate_filtering_outs}/{}/{}_{}.tsv"
    ch_model_snv = channel.fromPath(
        "${params.outdir}/${params.data_staging_outs}/${params.models_dir}/extra_trees.snv.joblib",
        checkIfExists: true
    )
    ch_model_indel = channel.fromPath(
        "${params.outdir}/${params.data_staging_outs}/${params.models_dir}/extra_trees.indel.joblib",
        checkIfExists: true
    )

    VARIANTMEDIUM_FILTER_CANDIDATES(
        ch_samples_w_cands,
        ch_outdir_filter,
        ch_model_snv,
        ch_model_indel
    )

    // step 7: tensor generation (bam2tensor)
    TENSOR_GENERATION(
        ch_tsv_folder.map { it.find { f -> f.name == 'pairs_w_cands.tsv' } },
        ref,
        params.outdir
    )

    ch_tensor_dir = params.skip_tensor_generation
        ? channel.fromPath("${params.outdir}/output_01_05_tensors", checkIfExists: true)
        : TENSOR_GENERATION.out.tensor_dir

    // step 8: DenseNet variant calling
    ch_model_snv_pt = channel.fromPath(
        "${params.outdir}/${params.data_staging_outs}/${params.models_dir}/3ddensenet_snv.pt",
        checkIfExists: true
    )
    ch_model_indel_pt = channel.fromPath(
        "${params.outdir}/${params.data_staging_outs}/${params.models_dir}/3ddensenet_indel.pt",
        checkIfExists: true
    )

    VARIANTMEDIUM_CALL_VARIANTS(
        ch_tensor_dir,
        ch_model_snv_pt,
        ch_model_indel_pt
    )
}