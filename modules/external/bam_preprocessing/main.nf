process BAM_PREPROCESSING {
    label 'process_local'

    when:
    !params.skip_preprocessing

    input:
    path(preproc_tsv)
    val(ref)
    val(exome_bed)
    val(dbsnp)
    val(known_indels1)
    val(outdir)

    output:
    path("${outdir}/output_01_01_preprocessed_bams"), emit: bam_dir

    script:
    def bam_prep_config = params.bam_prep_config ? "-c ${params.bam_prep_config}" : ''
    def resume          = params.resume ? '-resume' : ''
    """
    nextflow run tron-bioinformatics/tronflow-bam-preprocessing \\
        -r ${params.external.bam_preprocessing_version} \\
        -profile ${params.nf_profile} \\
        --input_files ${preproc_tsv} \\
        --reference ${ref} \\
        --intervals ${exome_bed} \\
        --dbsnp ${dbsnp} \\
        --known_indels1 ${known_indels1} \\
        --output ${outdir}/output_01_01_preprocessed_bams \\
        --skip_deduplication \\
        --skip_metrics \\
        ${bam_prep_config} \\
        ${resume}
    """
}