#!/bin/bash
# Created by: Andreas Wilke - Palo Alto Networks
# Tested with Prisma Cloud Compute version: 20_04_177

PCC_USER="${PCC_USER:-$PCC_USER}"
PCC_USER_PW="${PCC_USER_PW:-NONE}"
PCC_CONSOLE="${PCC_CONSOLE:-NONE}"
REGISTRY="${REGISTRY:-myregistry.test.com}"

usage() {
  local scriptnm="${0##*/}"
  local docstring="Usage:
  ${scriptnm} [ -a PCC_CONSOLE ] [ -u PCC_USER ] [ -r REGISTRY ]\n
  Options:
    -a PCC_CONSOLE     the Console URL (eg - https://console.address:8083).
    -u PCC_USER     authenticate using this Console user account (default: $PCC_USER)
    -r REGISTRY    the name of the registry used to create the filter on images with namespace as repository name.
  Environment variables:
    All command line parameters can be passed as environment variables
    using the name listed above, eg - set the variable PCC_CONSOLE to the
    address of the Console rather than passing the -a flag. Options passed on
    the command-line override environment variables. The Console user's password
    can be passed via the PCC_USER_PW environment variable\n
  Requires:
    The curl, jq, and kubectl commands.\n"

   echo -e "${docstring}" | sed 's/^  //g'
}

get_namespaces() {
  kubectl get namespace -o jsonpath="{..name}" |\
  tr -s '[[:space:]]' '\n' |\
  sort |\
  uniq -c |\
  awk '{print $2}'
}

get_collections_names() {
  curl -s -k -u "${PCC_USER}:${PCC_USER_PW}" -H 'Content-Type: application/json' "${PCC_CONSOLE_API}/${api_path}" |\
  tr ',' '\n' |\
  sed 's/"//g' |\
  grep -i 'name:' |\
  cut -f2 -d:
}

# Defining http request method to POST for new Collections
http_req_method="POST"
# the base end point for defining Collections
api_path="collections"

while getopts ":hn:r:u:a:" OPTION; do
  case "${OPTION}" in
    u) PCC_USER="${OPTARG}";;
    a) PCC_CONSOLE="${OPTARG}";;
    r) REGISTRY="${OPTARG}";;
    h) usage
       exit 1;;
    *) usage
       echo "ERROR: unknown option -${OPTARG}"
       exit 1;;
  esac
done

arg_err=""
if [[ "${PCC_USER}" == NONE ]]; then
  arg_err="missing the PCC_USER argument (-u)"
fi
if [[ "${PCC_CONSOLE}" == NONE ]]; then
  if [[ "${arg_err}X" == X ]] ; then
     arg_err="missing the PCC_CONSOLE argument (-a)"
  else
     arg_err="${arg_err}, missing the PCC_CONSOLE argument (-a)"
  fi
fi

if [[ "${arg_err}X" != X ]]; then
   usage
   echo "ERROR: ${arg_err}"
   exit 2
fi

PCC_USER_PW="MyDemo123#"

if [[ "${PCC_USER_PW}" == NONE ]]; then
   read -s -p "enter password for ${PCC_USER}: " PCC_USER_PW
fi

# Build the PrismaCloudCompute API String
PCC_CONSOLE_API="$PCC_CONSOLE/api/v1"
echo "----------------------------"
echo "Prisma Cloud Compute API:"
echo $PCC_CONSOLE_API
echo "----------------------------"
echo ""
# Get all the current namspaces in Kubernetes
NAMESPACES=$(get_namespaces)
echo "----------------------------"
echo "Found Namespaces:"
echo "$NAMESPACES"
echo "----------------------------"
echo ""
# Get all the current collections defined inside the Prisma Cloud Compute Console
COLLECTIONS=$(get_collections_names)
echo "----------------------------"
echo "Found Collections:"
echo "$COLLECTIONS"
echo "----------------------------"
echo ""

# For each Namspace check if a collection for it existis within Prisma Cloud Compute
# If Not, create a collection with filter on REGISTRY/NAMESPACE/* for Images
# If Yes, do nothing
echo "----------------------------"
echo "Creating Missing Collections:"
for namespace in $NAMESPACES
do
 collection_exists=false
 for collection in $COLLECTIONS
 do
  if [ "$collection" == "$namespace" ]
  then
   collection_exists=true
  fi
 done
 if [ "$collection_exists" == true ]
 then
   echo "Collection for Namespace $namespace already exists. Doing nothing..."
 else
   echo "Collection for Namespace $namespace doesn't exist. Creating it..."
   http_req_method="POST"
   curl -s -k -u "${PCC_USER}:${PCC_USER_PW}" \
    -X "${http_req_method}" \
    -H 'Content-Type: application/json' \
    -d "{ \
    \"name\":\"${namespace}\", \
    \"color\":\"#ff0000\", \
    \"description\": \
    \"A collection for images within namespace ${namespace}\", \
    \"images\":[\"${REGISTRY}/${namespace}/*\"], \
    \"hosts\":[\"*\"], \
    \"services\":[\"*\"], \
    \"appIDs\":[\"*\"], \
    \"accountIDs\":[\"*\"], \
    \"hosts\":[\"*\"], \
    \"containers\":[\"*\"], \
    \"labels\":[\"*\"], \
    \"functions\":[\"*\"], \
    \"namespaces\":[\"*\"]}" \
    "${PCC_CONSOLE_API}/${api_path}"
  fi
done
echo "----------------------------"
