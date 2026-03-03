process FEATURE_GENERATION {
    label 'process_local'

    when:
    !params.skip_feature_generation

    input:
    path(vcfs_tsv)
    path(bams_tsv)
    val(ref)
    val(outdir)

    output:
    path("${outdir}/output_01_03_vcf_postprocessing"), emit: features_dir

    script:
    def vcf_post_config = params.vcf_post_config ? "-c ${params.vcf_post_config}" : ''
    def resume          = params.resume ? '-resume' : ''
    """
    nextflow run tron-bioinformatics/tronflow-vcf-postprocessing \\
        -r ${params.external.vcf_postprocessing_version} \\
        -profile ${params.nf_profile} \\
        --input_vcfs ${vcfs_tsv} \\
        --input_bams ${bams_tsv} \\
        --reference ${ref} \\
        --output ${outdir}/output_01_03_vcf_postprocessing \\
        --cpus ${params.vcf_post_cpus} \\
        --memory ${params.vcf_post_memory} \\
        ${vcf_post_config} \\
        ${resume}
    """
}