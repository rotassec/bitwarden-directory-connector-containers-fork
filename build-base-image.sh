#!/bin/bash

# Constants
SCRIPT_DIR="$( cd "$( dirname "${0}" )" && pwd )"
SCRIPT_NAME="$( basename "${0}" )"
# Source conf file with defaults
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/defaults.conf"
DEFAULT_BWDC_VERSION="${BWDC_VERSION}"

# Configurable args
MAKE_IT_SO=
NO_CACHE=
# If a custom conf, source it for overrides
# shellcheck disable=SC1091
[ -e "${SCRIPT_DIR}/custom.conf" ] && . "${SCRIPT_DIR}/custom.conf"

USAGE_HELP=0
USAGE_ERROR=255
usage() {
  cat <<EOM
  USAGE:
    ${SCRIPT_NAME} -c [-b BWDC_VERSION] [-n] [-u]

   - -c is the Confirmation flag that you actually meant to execute the script
   - BWDC_VERSION (default=${DEFAULT_BWDC_VERSION}) is X.Y.Z format (no leading v!) and one of: https://github.com/bitwarden/directory-connector/releases
   - Use "-n" to build container image without cache (podman --no-cache)
   - Use "-u" to view the How-to run bwdc-base usage

EOM

  # If usage was called without args, exit as error
  RC="${1:-USAGE_ERROR}"
  exit "${RC}"
}

# Build common base image
buildBase() {
  # shellcheck disable=SC2153
  podman build ${NO_CACHE} \
    --build-arg BWDC_VERSION="${BWDC_VERSION}" \
    -t "${IMAGE_NAMESPACE}"/bwdc-base:"${BWDC_VERSION}" \
    -t "${IMAGE_NAMESPACE}"/bwdc-base:"${BDCC_VERSION}" \
    -f Containerfile \
    || exit 1
}

# Convenient blurb to let you know how to run the container
usageRun() {

  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}"/functions.sh
  export BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE="\$BITWARDENCLI_CONNECTOR_DIRECTORY_TYPE"
  export SECRETS_MANAGER="env"
  SECRETS="$( buildPodmanRunSecretsOptions )"

  cat <<-EOM
	===========================================================================
	  To run the generic base container using your own data.json file
	  NON-INTERACTIVELY, mount the directory containing your data.json file
	  ==> THIS WILL RESULT IN DATA.JSON BEING MODIFIED (bwdc behavior). <==

	  Published version:
	    podman run ${SECRETS} --rm --volume /PATH/TO/YOUR/DATA-JSON-DIR:/bwdc/.config/Bitwarden\ Directory\ Connector --userns=keep-id ghcr.io/hdub-tech/bwdc-base:${BWDC_VERSION} [-c] [-t] [-s] [-h]

	  Local version:
	    podman run ${SECRETS} --rm --volume /PATH/TO/YOUR/DATA-JSON-DIR:/bwdc/.config/Bitwarden\ Directory\ Connector --userns=keep-id ${IMAGE_NAMESPACE}/bwdc-base:${BWDC_VERSION} [-c] [-t] [-s] [-h]
	----------------------------------------------------------------------------
	  To run the generic base container using your own data.json file
	  INTERACTIVELY, mount the directory containing your data.json file
	  ==> THIS WILL RESULT IN DATA.JSON BEING MODIFIED IF YOU USE bwdc <==

	  Published version:
	    podman run ${SECRETS} -it --rm --entrypoint bash --volume /PATH/TO/YOUR/DATA-JSON-DIR:/bwdc/.config/Bitwarden\ Directory\ Connector --userns=keep-id ghcr.io/hdub-tech/bwdc-base:${BWDC_VERSION}

	  Local version:
	    podman run ${SECRETS} -it --rm --entrypoint bash --volume /PATH/TO/YOUR/DATA-JSON-DIR:/bwdc/.config/Bitwarden\ Directory\ Connector --userns=keep-id ${IMAGE_NAMESPACE}/bwdc-base:${BWDC_VERSION}

	===========================================================================
	EOM
}

while getopts "chub:n" opt; do
  case "${opt}" in
    "h" )
      # h = help
      usage "${USAGE_HELP}" ;;
    "u" )
      # u = usage run statement
      USAGE_RUN=true
      ;;
    "c" )
      # confirmed
      MAKE_IT_SO=true
      ;;
    "b" )
      # b = BWDC version
      BWDC_VERSION="${OPTARG}" ;;
    "n" )
      # n = no-cache
      NO_CACHE="--no-cache" ;;
    * ) usage "${USAGE_ERROR}" ;;
  esac
done

if [ -z "${MAKE_IT_SO}" ] && [ -z "${USAGE_RUN}" ]; then
  usage 2
else
  [ -n "${MAKE_IT_SO}" ] && buildBase
  [ -n "${USAGE_RUN}" ] && usageRun
  exit 0
fi
