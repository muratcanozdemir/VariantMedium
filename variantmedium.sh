#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# -------------------------------------------------------
# VariantMedium pipeline launcher
# -------------------------------------------------------

VERSION="1.2.0"

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------

log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

die() {
    log "ERROR: $1" >&2
    exit 1
}

usage() {
    cat <<EOF

VariantMedium pipeline launcher v${VERSION}

USAGE:
  $(basename "$0") [OPTIONS]

REQUIRED:
  --samplesheet   PATH    Path to input CSV/TSV samplesheet
  --outdir        PATH    Output directory for all pipeline results
  --profile       STRING  Nextflow profile: conda, docker, singularity [default: conda]

OPTIONAL:
  --config        PATH    Path to custom Nextflow params config (.conf)
  --mount-path    PATH    Bind mount path (required for singularity profile)
  --ref           PATH    Reference genome FASTA (overrides data staging output)
  --exome-bed     PATH    Exome target BED.gz (overrides data staging output)
  --dbsnp         PATH    dbSNP VCF.gz (overrides data staging output)
  --known-indels  PATH    Known indels VCF.gz (overrides data staging output)

SKIP FLAGS:
  --skip-data-staging         Skip staging reference data and models
  --skip-preprocessing        Skip BAM preprocessing
  --skip-candidate-calling    Skip Strelka2 candidate calling
  --skip-feature-generation   Skip VCF postprocessing / feature generation
  --skip-candidate-filtering  Skip ExtraTrees candidate filtering
  --skip-tensor-generation    Skip bam2tensor tensor generation

NEXTFLOW OPTIONS:
  --resume        Resume from previous run
  --nf-report     Generate Nextflow execution report
  --nf-trace      Generate Nextflow execution trace

CUSTOM SUB-PIPELINE CONFIGS:
  --bam-prep-config     PATH    Custom config for tronflow-bam-preprocessing
  --strelka-config      PATH    Custom config for tronflow-strelka2
  --vcf-post-config     PATH    Custom config for tronflow-vcf-postprocessing
  --bam2tensor-config   PATH    Custom config for bam2tensor

  -h, --help      Show this message and exit

EOF
    exit 0
}

# -------------------------------------------------------
# Defaults
# -------------------------------------------------------

SAMPLESHEET=""
OUTDIR=""
PROFILE="conda"
CONFIG_FILE=""
MOUNT_PATH=""
REF=""
EXOME_BED=""
DBSNP=""
KNOWN_INDELS1=""

SKIP_DATA_STAGING=false
SKIP_PREPROCESSING=false
SKIP_CANDIDATE_CALLING=false
SKIP_FEATURE_GENERATION=false
SKIP_CANDIDATE_FILTERING=false
SKIP_TENSOR_GENERATION=false

RESUME=""
REQUEST_REPORT=false
REQUEST_TRACE=false

BAM_PREP_CONFIG=""
STRELKA_CONFIG=""
VCF_POST_CONFIG=""
BAM2TENSOR_CONFIG=""

# -------------------------------------------------------
# Argument parsing
# -------------------------------------------------------

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --samplesheet)        SAMPLESHEET="$2";     shift 2 ;;
        --outdir)             OUTDIR="$2";           shift 2 ;;
        --profile)            PROFILE="$2";          shift 2 ;;
        --config)             CONFIG_FILE="$2";      shift 2 ;;
        --mount-path)         MOUNT_PATH="$2";       shift 2 ;;
        --ref)                REF="$2";              shift 2 ;;
        --exome-bed)          EXOME_BED="$2";        shift 2 ;;
        --dbsnp)              DBSNP="$2";            shift 2 ;;
        --known-indels)       KNOWN_INDELS1="$2";    shift 2 ;;
        --skip-data-staging)       SKIP_DATA_STAGING=true;        shift ;;
        --skip-preprocessing)      SKIP_PREPROCESSING=true;       shift ;;
        --skip-candidate-calling)  SKIP_CANDIDATE_CALLING=true;   shift ;;
        --skip-feature-generation) SKIP_FEATURE_GENERATION=true;  shift ;;
        --skip-candidate-filtering)SKIP_CANDIDATE_FILTERING=true; shift ;;
        --skip-tensor-generation)  SKIP_TENSOR_GENERATION=true;   shift ;;
        --resume)             RESUME="-resume";      shift ;;
        --nf-report)          REQUEST_REPORT=true;   shift ;;
        --nf-trace)           REQUEST_TRACE=true;    shift ;;
        --bam-prep-config)    BAM_PREP_CONFIG="$2";  shift 2 ;;
        --strelka-config)     STRELKA_CONFIG="$2";   shift 2 ;;
        --vcf-post-config)    VCF_POST_CONFIG="$2";  shift 2 ;;
        --bam2tensor-config)  BAM2TENSOR_CONFIG="$2";shift 2 ;;
        -h|--help)            usage ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# -------------------------------------------------------
# Load optional config file
# -------------------------------------------------------

if [[ -n "$CONFIG_FILE" ]]; then
    [[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"
    log "Loading config: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# -------------------------------------------------------
# Validate required arguments
# -------------------------------------------------------

[[ -n "$SAMPLESHEET" ]] || die "--samplesheet is required"
[[ -n "$OUTDIR"      ]] || die "--outdir is required"
[[ -n "$PROFILE"     ]] || die "--profile is required"

[[ -f "$SAMPLESHEET" ]] || die "Samplesheet does not exist: $SAMPLESHEET"

SAMPLESHEET="$(realpath "$SAMPLESHEET")"
OUTDIR="$(realpath -m "$OUTDIR")"

# -------------------------------------------------------
# Profile-specific validation
# -------------------------------------------------------

case "$PROFILE" in
    conda|docker|singularity) ;;
    *) die "Unknown profile '${PROFILE}'. Must be one of: conda, docker, singularity" ;;
esac

if [[ "$PROFILE" == "singularity" ]]; then
    [[ -n "$MOUNT_PATH" ]] || die "--mount-path is required when using the singularity profile"
    [[ -d "$MOUNT_PATH" ]] || die "Mount path does not exist: $MOUNT_PATH"
    MOUNT_PATH="$(realpath "$MOUNT_PATH")"
fi

# -------------------------------------------------------
# Skip flag validation
# -------------------------------------------------------

if [[ "$SKIP_DATA_STAGING" == true ]]; then
    # Reference paths must be resolvable if data staging is skipped.
    # They can come from --ref/--exome-bed/etc. flags or from the config file.
    # If still empty, default derivation will proceed from OUTDIR — warn only.
    if [[ -z "$REF" ]]; then
        log "WARNING: --skip-data-staging set but --ref not provided. Defaulting to outdir-relative path."
    fi
fi

# Validate any explicitly provided reference paths
for varname in REF EXOME_BED DBSNP KNOWN_INDELS1; do
    val="${!varname}"
    if [[ -n "$val" ]]; then
        [[ -f "$val" ]] || die "${varname} path does not exist: $val"
        printf -v "$varname" '%s' "$(realpath "$val")"
    fi
done

# Validate custom sub-pipeline configs
for varname in BAM_PREP_CONFIG STRELKA_CONFIG VCF_POST_CONFIG BAM2TENSOR_CONFIG; do
    val="${!varname}"
    if [[ -n "$val" ]]; then
        [[ -f "$val" ]] || die "${varname} config file does not exist: $val"
        printf -v "$varname" '%s' "$(realpath "$val")"
    fi
done

# -------------------------------------------------------
# Build Nextflow report/trace args
# -------------------------------------------------------

NF_REPORT_ARGS=()
if [[ "$REQUEST_REPORT" == true ]]; then
    NF_REPORT_ARGS+=("-with-report" "${OUTDIR}/benchmarks/report.html")
fi
if [[ "$REQUEST_TRACE" == true ]]; then
    NF_REPORT_ARGS+=("-with-trace" "${OUTDIR}/benchmarks/trace.txt")
fi

# -------------------------------------------------------
# Build optional Nextflow params
# -------------------------------------------------------

NF_PARAMS=()

# reference overrides — only passed if explicitly set, otherwise
# main.nf derives them from the data staging output directory
[[ -n "$REF"          ]] && NF_PARAMS+=(--ref           "$REF")
[[ -n "$EXOME_BED"    ]] && NF_PARAMS+=(--exome_bed     "$EXOME_BED")
[[ -n "$DBSNP"        ]] && NF_PARAMS+=(--dbsnp         "$DBSNP")
[[ -n "$KNOWN_INDELS1"]] && NF_PARAMS+=(--known_indels1 "$KNOWN_INDELS1")

# singularity bind mount
[[ -n "$MOUNT_PATH"   ]] && NF_PARAMS+=(--mount_path    "$MOUNT_PATH")

# custom sub-pipeline configs
[[ -n "$BAM_PREP_CONFIG"   ]] && NF_PARAMS+=(--bam_prep_config   "$BAM_PREP_CONFIG")
[[ -n "$STRELKA_CONFIG"    ]] && NF_PARAMS+=(--strelka_config    "$STRELKA_CONFIG")
[[ -n "$VCF_POST_CONFIG"   ]] && NF_PARAMS+=(--vcf_post_config   "$VCF_POST_CONFIG")
[[ -n "$BAM2TENSOR_CONFIG" ]] && NF_PARAMS+=(--bam2tensor_config "$BAM2TENSOR_CONFIG")

# skip flags
[[ "$SKIP_DATA_STAGING"         == true ]] && NF_PARAMS+=(--run_data_staging       false)
[[ "$SKIP_PREPROCESSING"        == true ]] && NF_PARAMS+=(--skip_preprocessing        true)
[[ "$SKIP_CANDIDATE_CALLING"    == true ]] && NF_PARAMS+=(--skip_candidate_calling    true)
[[ "$SKIP_FEATURE_GENERATION"   == true ]] && NF_PARAMS+=(--skip_feature_generation   true)
[[ "$SKIP_CANDIDATE_FILTERING"  == true ]] && NF_PARAMS+=(--skip_candidate_filtering  true)
[[ "$SKIP_TENSOR_GENERATION"    == true ]] && NF_PARAMS+=(--skip_tensor_generation    true)

# -------------------------------------------------------
# Summary
# -------------------------------------------------------

log "---------------------------------------------"
log "  VariantMedium v${VERSION}"
log "  Samplesheet              : $SAMPLESHEET"
log "  Output dir               : $OUTDIR"
log "  Profile                  : $PROFILE"
log "  Config file              : ${CONFIG_FILE:-<none>}"
log "  Skip data staging        : $SKIP_DATA_STAGING"
log "  Skip preprocessing       : $SKIP_PREPROCESSING"
log "  Skip candidate calling   : $SKIP_CANDIDATE_CALLING"
log "  Skip feature generation  : $SKIP_FEATURE_GENERATION"
log "  Skip candidate filtering : $SKIP_CANDIDATE_FILTERING"
log "  Skip tensor generation   : $SKIP_TENSOR_GENERATION"
log "  Reference                : ${REF:-<from data staging>}"
log "  Exome BED                : ${EXOME_BED:-<from data staging>}"
log "  dbSNP                    : ${DBSNP:-<from data staging>}"
log "  Known indels             : ${KNOWN_INDELS1:-<from data staging>}"
log "  Mount path               : ${MOUNT_PATH:-<none>}"
log "  Resume                   : ${RESUME:--no-}"
log "  NF report                : $REQUEST_REPORT"
log "  NF trace                 : $REQUEST_TRACE"
log "---------------------------------------------"

# -------------------------------------------------------
# Run
# -------------------------------------------------------

mkdir -p "${OUTDIR}/benchmarks"

nextflow run "tron-bioinformatics/VariantMedium" \
    -r "${VERSION}" \
    -profile "${PROFILE}" \
    --samplesheet  "$SAMPLESHEET" \
    --outdir       "$OUTDIR" \
    --nf_profile   "$PROFILE" \
    "${NF_PARAMS[@]}" \
    "${NF_REPORT_ARGS[@]}" \
    ${RESUME}