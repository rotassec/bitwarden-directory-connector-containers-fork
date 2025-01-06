#!/bin/bash

# TODO convert to compose file?

SCRIPT_DIR="$( cd "$( dirname "${0}" )" && pwd )"
SCRIPT_NAME="$( basename "${0}" )"
SUPPORTED_BWDC_SYNCS=( gsuite )
SUPPORTED_SECRETS_MANAGERS=( podman env )
DEFAULT_BWDC_VERSION=2024.10.0
BASE_VERSION="1.0.0-alpha"
GSUITE_VERSION="1.0.0-alpha"

# Configurable args
BWDC_VERSION="${DEFAULT_BWDC_VERSION}"
BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE=
SECRETS_MANAGER=
NO_CACHE=
OPTIONAL_REBUILD_BWDC_LOGIN_STAGE=

USAGE_HELP=0
USAGE_ERROR=255
usage() {
  cat <<EOM
  USAGE:
    ${SCRIPT_NAME} -t BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE [-s SECRETS_MANAGER] [-b BWDC_VERSION] [-n] [-r]

   - BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE is one of: ${SUPPORTED_BWDC_SYNCS[*]}
   - SECRETS_MANAGER is one of: ${SUPPORTED_SECRETS_MANAGERS[*]}
     Note: "env" (default) indicates that the secrets are already exported to the environment.
   - BWDC_VERSION (default=${DEFAULT_BWDC_VERSION}) is X.Y.Z format and one of: https://github.com/bitwarden/directory-connector/releases
   - Use "-n" to build all Docker images without cache (--no-cache)
   - Use "-r" to rebuild the final run stage of the type specific container (allows you to test login)

EOM

  # If usage was called without args, exit as error
  RC="${1:-USAGE_ERROR}"
  exit "${RC}"
}

# uppercase all arguments
uppercase() {
  if [ "$#" -lt 1 ]; then
    echo "uppercase requires at least 1 arg"
    exit 4
  fi

  echo "$@" | tr '[:lower:]' '[:upper:]'
}

# extract the specified podman secrets to a corresponding environment var
exportPodmanSecrets() {
  for psecret in "$@" ; do
    if podman secret exists "${psecret}"; then
      declare -a FILE_AND_ID
      # Select the file with the specified secret as well as its Hex ID
      mapfile -t FILE_AND_ID < <( podman secret inspect "${psecret}" | jq -r '.[0].Spec.Driver.Options.path, .[0].ID' )
      # Extract the encoded secret from file using its Hex ID and b64 decode
      SECRET_VALUE=$( jq -r --arg secretid "${FILE_AND_ID[1]}" '.[$secretid] | @base64d' "${FILE_AND_ID[0]}"/secretsdata.json )
      SECRET_KEY="$( uppercase "${psecret}" )"
      export "${SECRET_KEY}"="${SECRET_VALUE}"
    else
      echo "${psecret} doesn't exist in podman local storage"
      exit 5
    fi
  done
}

# env secrets SHOULD already be exported in this env and this confirms it
confirmEnvSecrets() {
  for env in "$@"; do
    if [ -z "${!env}" ]; then  # The ! allows Indirect Ref to env var
      echo "SECRETS_MANAGER=env but ${env} not exported in this environment"
      exit 6
    fi
  done
}

# Generic export secrets function with error handling, calls exports by type
exportSecrets() {
  if [ "$#" -lt 1 ]; then
    echo "USAGE: ${0} secretid1 [secretid2 ... secretidN]"
    exit 7
  fi

  case "${SECRETS_MANAGER}" in
    "podman" ) exportPodmanSecrets "$@" ;;
    "env" )
      # shellcheck disable=SC2048,SC2086
      confirmEnvSecrets ${*@U} ;;
  esac
}

# Build common base image
buildBase() {
  podman build ${NO_CACHE} \
    --build-arg VERSION="${BASE_VERSION}" \
    --build-arg BWDC_VERSION="${BWDC_VERSION}" \
    -t hdub-tech/bwdc-base:"${BASE_VERSION}" \
    -f Dockerfile \
    || exit 9
}

# Build gsuite sync image
buildGsuite() {
  buildBase
  exportSecrets bw_clientid bw_clientsecret

  cd "${SCRIPT_DIR}"/"${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE}" \
    || (echo "Missing ${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE} subdir in ${SCRIPT_DIR}" \
       && exit 1)

  # shellcheck disable=SC2086
  podman build ${NO_CACHE} \
    ${OPTIONAL_REBUILD_BWDC_LOGIN_STAGE} \
    --build-arg-file=argfile.conf \
    --secret=id=bw_clientid,env=BW_CLIENTID \
    --secret=id=bw_clientsecret,env=BW_CLIENTSECRET \
    --build-arg BASE_VERSION="${BASE_VERSION}" \
    --build-arg VERSION="${GSUITE_VERSION}" \
    -t "hdub-tech/bwdc-${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE}":"${GSUITE_VERSION}" \
    -f Dockerfile \
    || exit 10
}

# Convenient blurb to let you know how to run the container
# TODO: This doesn't cover how to run with secrets as ENV vars (-s env)
usageRun() {
  declare -a SECRETS
  SECRETS+=("--secret=bw_clientid,type=env,target=BW_CLIENTID")
  SECRETS+=("--secret=bw_clientsecret,type=env,target=BW_CLIENTSECRET")
  SECRETS+=("--secret=bw_key,type=env,target=BW_KEY")

  cat <<EOM
    To run non-interactively:
      podman run ${SECRETS[*]} localhost/hdub-tech-bwdc-${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE}:${BWDC_VERSION} config|test|sync

    To run interactively:
      podman run ${SECRETS[*]} -it --entrypoint bash localhost/hdub-tech-bwdc-${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE}:${BWDC_VERSION}
EOM
}

# Simplistic check for simplistic use case
arrayContains() {
  if [ "$#" -ne 2 ]; then
    echo "USAGE: ${0} ARRAY SEARCH_ITEM"
    exit 8
  fi

  array="${1}"
  search_item="${2}"

  [[ " ${array[*]} " =~ [[:space:]]${search_item}[[:space:]] ]]
}

while getopts "ht:s:b:nr" opt; do
  case "${opt}" in
    "h" )
      # h = help
      usage "${USAGE_HELP}" ;;
    "t" )
      # t = type
      if arrayContains "${SUPPORTED_BWDC_SYNCS[*]}" "${OPTARG}" ; then
        BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE="${OPTARG}"
      else
        usage 1
      fi
      ;;
    "s" )
      # s = secret manager
      if arrayContains "${SUPPORTED_SECRETS_MANAGERS[*]}" "${OPTARG}" ; then
        SECRETS_MANAGER="${OPTARG}"
      else
        usage 2
      fi
      ;;
    "n" )
      # n = no-cache
      NO_CACHE="--no-cache" ;;
    "r" )
      # r = rebuild run stage
      OPTIONAL_REBUILD_BWDC_LOGIN_STAGE="--build-arg OPTIONAL_REBUILD_BWDC_LOGIN_STAGE=\"$( date +%s )\""
      ;;
    "b" )
      # b = BWDC version
      BWDC_VERSION="${OPTARG}"
      ;;
    * ) usage "${USAGE_ERROR}" ;;
  esac
done

if [ -z "${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE}" ] || [ -z "${SECRETS_MANAGER}" ]; then
  usage 3
else
  case "${BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE}" in
    "gsuite" ) buildGsuite ;;
  esac

  usageRun
fi