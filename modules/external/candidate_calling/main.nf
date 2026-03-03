process CANDIDATE_CALLING {
    label 'process_local'

    when:
    !params.skip_candidate_calling

    input:
    path(pairs_tsv)
    val(ref)
    val(exome_bed)
    val(outdir)

    output:
    path("${outdir}/output_01_02_candidates_strelka2"), emit: vcf_dir

    script:
    def intervals      = exome_bed ? "--intervals ${exome_bed}" : ''
    def strelka_config = params.strelka_config ? "-c ${params.strelka_config}" : ''
    def resume         = params.resume ? '-resume' : ''
    """
    nextflow run tron-bioinformatics/tronflow-strelka2 \\
        -r ${params.external.strelka2_version} \\
        -profile ${params.nf_profile} \\
        --input_files ${pairs_tsv} \\
        --reference ${ref} \\
        --output ${outdir}/output_01_02_candidates_strelka2 \\
        --cpus ${params.strelka2_cpus} \\
        --memory ${params.strelka2_memory} \\
        ${intervals} \\
        ${strelka_config} \\
        ${resume}
    """
}