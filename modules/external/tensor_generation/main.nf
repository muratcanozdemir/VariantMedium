process TENSOR_GENERATION {
    label 'process_local'

    when:
    !params.skip_tensor_generation

    input:
    path(pairs_w_cands_tsv)
    val(ref)
    val(outdir)

    output:
    path("${outdir}/output_01_05_tensors"), emit: tensor_dir

    script:
    def bam2tensor_config = params.bam2tensor_config ? "-c ${params.bam2tensor_config}" : ''
    def resume            = params.resume ? '-resume' : ''
    """
    nextflow run tron-bioinformatics/bam2tensor \\
        -r ${params.external.bam2tensor_version} \\
        -profile ${params.nf_profile} \\
        --input_files ${pairs_w_cands_tsv} \\
        --publish_dir ${outdir}/output_01_05_tensors \\
        --reference ${ref} \\
        --cpus ${params.bam2tensor_cpus} \\
        --memory ${params.bam2tensor_memory} \\
        --window 150 \\
        --max_coverage 500 \\
        --read_length 50 \\
        --max_mapq 60 \\
        --max_baseq 82 \\
        ${bam2tensor_config} \\
        ${resume}
    """
}