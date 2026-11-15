#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT_DIR}/k8s/workload-job.yaml.tpl"
NAMESPACE_FILE="${ROOT_DIR}/k8s/namespace.yaml"

LEVEL="${LEVEL:-light}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dt%H%M%Sz)}"
RUN_ID="$(printf '%s' "${RUN_ID}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//; s/--*/-/g')"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/results/${RUN_ID}/${LEVEL}}"
MAX_NODE_COUNT="${MAX_NODE_COUNT:-3}"
SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-10}"

if [[ -z "${RUN_ID}" ]]; then
  echo "RUN_ID must contain at least one letter or number after normalization." >&2
  exit 2
fi

case "${LEVEL}" in
  light)
    REPLICAS="${REPLICAS:-1}"
    INPUT_SIZE="${INPUT_SIZE:-150000}"
    MAX_DURATION_SECONDS="${MAX_DURATION_SECONDS:-90}"
    CPU_WORKERS="${CPU_WORKERS:-1}"
    MEMORY_MB="${MEMORY_MB:-96}"
    CPU_REQUEST="${CPU_REQUEST:-250m}"
    CPU_LIMIT="${CPU_LIMIT:-500m}"
    MEMORY_REQUEST="${MEMORY_REQUEST:-160Mi}"
    MEMORY_LIMIT="${MEMORY_LIMIT:-256Mi}"
    ;;
  medium)
    REPLICAS="${REPLICAS:-4}"
    INPUT_SIZE="${INPUT_SIZE:-400000}"
    MAX_DURATION_SECONDS="${MAX_DURATION_SECONDS:-180}"
    CPU_WORKERS="${CPU_WORKERS:-1}"
    MEMORY_MB="${MEMORY_MB:-192}"
    CPU_REQUEST="${CPU_REQUEST:-500m}"
    CPU_LIMIT="${CPU_LIMIT:-1000m}"
    MEMORY_REQUEST="${MEMORY_REQUEST:-320Mi}"
    MEMORY_LIMIT="${MEMORY_LIMIT:-512Mi}"
    ;;
  heavy)
    REPLICAS="${REPLICAS:-8}"
    INPUT_SIZE="${INPUT_SIZE:-800000}"
    MAX_DURATION_SECONDS="${MAX_DURATION_SECONDS:-300}"
    CPU_WORKERS="${CPU_WORKERS:-2}"
    MEMORY_MB="${MEMORY_MB:-384}"
    CPU_REQUEST="${CPU_REQUEST:-1000m}"
    CPU_LIMIT="${CPU_LIMIT:-2000m}"
    MEMORY_REQUEST="${MEMORY_REQUEST:-640Mi}"
    MEMORY_LIMIT="${MEMORY_LIMIT:-1024Mi}"
    ;;
  *)
    echo "LEVEL must be one of: light, medium, heavy" >&2
    exit 2
    ;;
esac

JOB_NAME="workload-${LEVEL}-${RUN_ID}"
ACTIVE_DEADLINE_SECONDS=$((MAX_DURATION_SECONDS + 60))

mkdir -p "${OUTPUT_DIR}/top" "${OUTPUT_DIR}/events"
SAMPLES_CSV="${OUTPUT_DIR}/samples.csv"
RESULT_JSON="${OUTPUT_DIR}/result.json"
MANIFEST_OUT="${OUTPUT_DIR}/workload.yaml"

render_manifest() {
  sed \
    -e "s#__LEVEL__#${LEVEL}#g" \
    -e "s#__RUN_ID__#${RUN_ID}#g" \
    -e "s#__REPLICAS__#${REPLICAS}#g" \
    -e "s#__ACTIVE_DEADLINE_SECONDS__#${ACTIVE_DEADLINE_SECONDS}#g" \
    -e "s#__MAX_DURATION_SECONDS__#${MAX_DURATION_SECONDS}#g" \
    -e "s#__INPUT_SIZE__#${INPUT_SIZE}#g" \
    -e "s#__MEMORY_MB__#${MEMORY_MB}#g" \
    -e "s#__CPU_WORKERS__#${CPU_WORKERS}#g" \
    -e "s#__CPU_REQUEST__#${CPU_REQUEST}#g" \
    -e "s#__CPU_LIMIT__#${CPU_LIMIT}#g" \
    -e "s#__MEMORY_REQUEST__#${MEMORY_REQUEST}#g" \
    -e "s#__MEMORY_LIMIT__#${MEMORY_LIMIT}#g" \
    "${TEMPLATE}" > "${MANIFEST_OUT}"
}

count_or_zero() {
  local command_output
  command_output="$("$@" 2>/dev/null || true)"
  if [[ -z "${command_output}" ]]; then
    echo 0
  else
    echo "${command_output}" | wc -l | tr -d ' '
  fi
}

job_condition() {
  kubectl -n eks-poc get job "${JOB_NAME}" -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{end}' 2>/dev/null || true
}

capture_sample() {
  local elapsed="$1"
  local stamp="$2"
  local index="$3"
  local top_nodes_file=""
  local top_pods_file=""
  local top_nodes_available="false"
  local top_pods_available="false"

  local node_count
  node_count="$(count_or_zero kubectl get nodes --no-headers)"

  local pod_count
  pod_count="$(count_or_zero kubectl -n eks-poc get pods -l "poc.run-id=${RUN_ID}" --no-headers)"

  local pending_pods
  pending_pods="$(count_or_zero kubectl -n eks-poc get pods -l "poc.run-id=${RUN_ID}" --field-selector=status.phase=Pending --no-headers)"

  top_nodes_file="top/nodes-${index}.txt"
  if kubectl top nodes > "${OUTPUT_DIR}/${top_nodes_file}" 2>/dev/null; then
    top_nodes_available="true"
  else
    rm -f "${OUTPUT_DIR}/${top_nodes_file}"
    top_nodes_file=""
  fi

  top_pods_file="top/pods-${index}.txt"
  if kubectl -n eks-poc top pods -l "poc.run-id=${RUN_ID}" > "${OUTPUT_DIR}/${top_pods_file}" 2>/dev/null; then
    top_pods_available="true"
  else
    rm -f "${OUTPUT_DIR}/${top_pods_file}"
    top_pods_file=""
  fi

  kubectl get events -A --sort-by=.lastTimestamp > "${OUTPUT_DIR}/events/events-${index}.txt" 2>/dev/null || true

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${stamp}" "${elapsed}" "${node_count}" "${pod_count}" "${pending_pods}" \
    "${top_nodes_available}" "${top_nodes_file}" "${top_pods_available}" "${top_pods_file}" >> "${SAMPLES_CSV}"
}

finish() {
  local status="$1"
  local stop_reason="$2"
  local started_at="$3"
  local finished_at
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local runtime_seconds
  runtime_seconds=$(( $(date -u +%s) - START_EPOCH ))

  cat > "${RESULT_JSON}" <<JSON
{
  "run_id": "${RUN_ID}",
  "workload_level": "${LEVEL}",
  "job_name": "${JOB_NAME}",
  "status": "${status}",
  "stop_reason": "${stop_reason}",
  "started_at": "${started_at}",
  "finished_at": "${finished_at}",
  "runtime_seconds": ${runtime_seconds},
  "parameters": {
    "replicas": ${REPLICAS},
    "input_size": ${INPUT_SIZE},
    "max_duration_seconds": ${MAX_DURATION_SECONDS},
    "cpu_workers": ${CPU_WORKERS},
    "memory_mb": ${MEMORY_MB},
    "cpu_request": "${CPU_REQUEST}",
    "cpu_limit": "${CPU_LIMIT}",
    "memory_request": "${MEMORY_REQUEST}",
    "memory_limit": "${MEMORY_LIMIT}",
    "max_node_count": ${MAX_NODE_COUNT}
  },
  "artifacts": {
    "samples_csv": "${SAMPLES_CSV}",
    "manifest": "${MANIFEST_OUT}",
    "events_dir": "${OUTPUT_DIR}/events"
  }
}
JSON
}

render_manifest
kubectl apply -f "${NAMESPACE_FILE}"
kubectl apply -f "${MANIFEST_OUT}"

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date -u +%s)"
printf 'timestamp,elapsed_seconds,node_count,pod_count,pending_pods,top_nodes_available,top_nodes_file,top_pods_available,top_pods_file\n' > "${SAMPLES_CSV}"

sample_index=0
saturated_samples=0

while true; do
  now_epoch="$(date -u +%s)"
  elapsed=$((now_epoch - START_EPOCH))
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  capture_sample "${elapsed}" "${stamp}" "${sample_index}"

  conditions="$(job_condition)"
  if [[ "${conditions}" == *"Complete=True"* ]]; then
    finish "succeeded" "job_completed" "${STARTED_AT}"
    break
  fi

  if [[ "${conditions}" == *"Failed=True"* ]]; then
    finish "failed" "job_failed" "${STARTED_AT}"
    break
  fi

  latest_node_count="$(tail -n 1 "${SAMPLES_CSV}" | awk -F, '{print $3}')"
  latest_pending_pods="$(tail -n 1 "${SAMPLES_CSV}" | awk -F, '{print $5}')"
  if [[ "${latest_node_count}" -ge "${MAX_NODE_COUNT}" && "${latest_pending_pods}" -gt 0 ]]; then
    saturated_samples=$((saturated_samples + 1))
  else
    saturated_samples=0
  fi

  if [[ "${saturated_samples}" -ge 3 ]]; then
    kubectl -n eks-poc delete job "${JOB_NAME}" --ignore-not-found=true
    finish "stopped" "max_nodes_with_pending_pods" "${STARTED_AT}"
    break
  fi

  if [[ "${elapsed}" -ge "${ACTIVE_DEADLINE_SECONDS}" ]]; then
    kubectl -n eks-poc delete job "${JOB_NAME}" --ignore-not-found=true
    finish "stopped" "runtime_limit_reached" "${STARTED_AT}"
    break
  fi

  sample_index=$((sample_index + 1))
  sleep "${SAMPLE_INTERVAL_SECONDS}"
done

kubectl -n eks-poc get job "${JOB_NAME}" -o yaml > "${OUTPUT_DIR}/job-final.yaml" 2>/dev/null || true
kubectl -n eks-poc get pods -l "poc.run-id=${RUN_ID}" -o wide > "${OUTPUT_DIR}/pods-final.txt" 2>/dev/null || true

echo "Result written to ${RESULT_JSON}"
