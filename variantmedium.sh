#!/usr/bin/env bash
set -Eeuo pipefail

cat >&2 <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                      DEPRECATION NOTICE                         ║
║                                                                  ║
║  variantmedium.sh is deprecated as of v1.2.0 and will be        ║
║  removed in the next release.                                    ║
║                                                                  ║
║  Run the pipeline directly with Nextflow:                        ║
║                                                                  ║
║    nextflow run tron-bioinformatics/VariantMedium \              ║
║      -r 1.2.0 \                                                  ║
║      -profile <conda|docker|singularity> \                       ║
║      --params-file my_run.yml                                    ║
║                                                                  ║
║  Minimal params file (my_run.yml):                               ║
║                                                                  ║
║    samplesheet: /path/to/samplesheet.tsv                         ║
║    outdir:      /path/to/output                                  ║
║                                                                  ║
║  Full parameter reference:                                       ║
║    https://github.com/TRON-Bioinformatics/VariantMedium          ║
║                                                                  ║
║  To suppress this warning and proceed anyway, re-run with:       ║
║    VARIANTMEDIUM_LEGACY=1 variantmedium.sh [OPTIONS]             ║
╚══════════════════════════════════════════════════════════════════╝
EOF

if [[ "${VARIANTMEDIUM_LEGACY:-0}" != "1" ]]; then
    exit 1
fi

echo "[INFO] VARIANTMEDIUM_LEGACY=1 set — proceeding with legacy launcher" >&2

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
die() { log "ERROR: $1" >&2; exit 1; }

usage() {
    cat <<EOF

VariantMedium legacy launcher (deprecated — see above)

USAGE:
  VARIANTMEDIUM_LEGACY=1 $(basename "$0") [OPTIONS]

REQUIRED:
  --samplesheet   PATH    Path to input CSV/TSV samplesheet
  --outdir        PATH    Output directory
  --profile       STRING  Nextflow profile: conda, docker, singularity

OPTIONAL:
  --params-file   PATH    Nextflow YAML params file (replaces run.conf)
  --mount-path    PATH    Bind mount path (singularity only)

SKIP FLAGS:
  --skip-data-staging
  --skip-preprocessing
  --skip-candidate-calling
  --skip-feature-generation
  --skip-candidate-filtering
  --skip-tensor-generation

NEXTFLOW OPTIONS:
  --resume
  --nf-report
  --nf-trace

  -h, --help

EOF
    exit 0
}

# -------------------------------------------------------
# Defaults
# -------------------------------------------------------

VERSION="1.2.0"
SAMPLESHEET=""
OUTDIR=""
PROFILE="conda"
PARAMS_FILE=""
MOUNT_PATH=""
RESUME=""
REQUEST_REPORT=false
REQUEST_TRACE=false

SKIP_DATA_STAGING=false
SKIP_PREPROCESSING=false
SKIP_CANDIDATE_CALLING=false
SKIP_FEATURE_GENERATION=false
SKIP_CANDIDATE_FILTERING=false
SKIP_TENSOR_GENERATION=false

# -------------------------------------------------------
# Argument parsing
# -------------------------------------------------------

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --samplesheet)              SAMPLESHEET="$2";  shift 2 ;;
        --outdir)                   OUTDIR="$2";        shift 2 ;;
        --profile)                  PROFILE="$2";       shift 2 ;;
        --params-file)              PARAMS_FILE="$2";   shift 2 ;;
        --mount-path)               MOUNT_PATH="$2";    shift 2 ;;
        --skip-data-staging)        SKIP_DATA_STAGING=true;        shift ;;
        --skip-preprocessing)       SKIP_PREPROCESSING=true;       shift ;;
        --skip-candidate-calling)   SKIP_CANDIDATE_CALLING=true;   shift ;;
        --skip-feature-generation)  SKIP_FEATURE_GENERATION=true;  shift ;;
        --skip-candidate-filtering) SKIP_CANDIDATE_FILTERING=true; shift ;;
        --skip-tensor-generation)   SKIP_TENSOR_GENERATION=true;   shift ;;
        --resume)                   RESUME="-resume";   shift ;;
        --nf-report)                REQUEST_REPORT=true; shift ;;
        --nf-trace)                 REQUEST_TRACE=true;  shift ;;
        -h|--help)                  usage ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# -------------------------------------------------------
# Validation
# -------------------------------------------------------

[[ -n "$SAMPLESHEET" ]] || die "--samplesheet is required"
[[ -n "$OUTDIR"      ]] || die "--outdir is required"
[[ -f "$SAMPLESHEET" ]] || die "Samplesheet does not exist: $SAMPLESHEET"

SAMPLESHEET="$(realpath "$SAMPLESHEET")"
OUTDIR="$(realpath -m "$OUTDIR")"

case "$PROFILE" in
    conda|docker|singularity) ;;
    *) die "Unknown profile '${PROFILE}'. Must be one of: conda, docker, singularity" ;;
esac

if [[ "$PROFILE" == "singularity" ]]; then
    [[ -n "$MOUNT_PATH" ]] || die "--mount-path is required for the singularity profile"
    [[ -d "$MOUNT_PATH" ]] || die "Mount path does not exist: $MOUNT_PATH"
    MOUNT_PATH="$(realpath "$MOUNT_PATH")"
fi

if [[ -n "$PARAMS_FILE" ]]; then
    [[ -f "$PARAMS_FILE" ]] || die "Params file does not exist: $PARAMS_FILE"
    PARAMS_FILE="$(realpath "$PARAMS_FILE")"
fi

# -------------------------------------------------------
# Build command
# -------------------------------------------------------

mkdir -p "${OUTDIR}/benchmarks"

CMD=(
    nextflow run "tron-bioinformatics/VariantMedium"
    -r "${VERSION}"
    -profile "${PROFILE}"
    --samplesheet "$SAMPLESHEET"
    --outdir      "$OUTDIR"
    --nf_profile  "$PROFILE"
)

[[ -n "$PARAMS_FILE"  ]] && CMD+=(-params-file "$PARAMS_FILE")
[[ -n "$MOUNT_PATH"   ]] && CMD+=(--mount_path "$MOUNT_PATH")
[[ -n "$RESUME"       ]] && CMD+=("$RESUME")

[[ "$SKIP_DATA_STAGING"        == true ]] && CMD+=(--run_data_staging       false)
[[ "$SKIP_PREPROCESSING"       == true ]] && CMD+=(--skip_preprocessing        true)
[[ "$SKIP_CANDIDATE_CALLING"   == true ]] && CMD+=(--skip_candidate_calling    true)
[[ "$SKIP_FEATURE_GENERATION"  == true ]] && CMD+=(--skip_feature_generation   true)
[[ "$SKIP_CANDIDATE_FILTERING" == true ]] && CMD+=(--skip_candidate_filtering  true)
[[ "$SKIP_TENSOR_GENERATION"   == true ]] && CMD+=(--skip_tensor_generation    true)

if [[ "$REQUEST_REPORT" == true ]]; then
    CMD+=(-with-report "${OUTDIR}/benchmarks/report.html")
fi
if [[ "$REQUEST_TRACE" == true ]]; then
    CMD+=(-with-trace "${OUTDIR}/benchmarks/trace.txt")
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------

log "---------------------------------------------"
log "  VariantMedium v${VERSION} (legacy launcher)"
log "  Samplesheet              : $SAMPLESHEET"
log "  Output dir               : $OUTDIR"
log "  Profile                  : $PROFILE"
log "  Params file              : ${PARAMS_FILE:-<none>}"
log "  Skip data staging        : $SKIP_DATA_STAGING"
log "  Skip preprocessing       : $SKIP_PREPROCESSING"
log "  Skip candidate calling   : $SKIP_CANDIDATE_CALLING"
log "  Skip feature generation  : $SKIP_FEATURE_GENERATION"
log "  Skip candidate filtering : $SKIP_CANDIDATE_FILTERING"
log "  Skip tensor generation   : $SKIP_TENSOR_GENERATION"
log "  Mount path               : ${MOUNT_PATH:-<none>}"
log "  Resume                   : ${RESUME:--no-}"
log "  NF report                : $REQUEST_REPORT"
log "  NF trace                 : $REQUEST_TRACE"
log "---------------------------------------------"
log "Running: ${CMD[*]}"

# -------------------------------------------------------
# Run
# -------------------------------------------------------

exec "${CMD[@]}"