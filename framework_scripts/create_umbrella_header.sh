#!/bin/bash
#
# Autogenerate the framework umbrella header from the headers in the includes directory.
#
# This scans the given INCLUDES_DIR for all header files and uses this information to
# populate the given HEADER_TEMPLATE file, outputting the result to HEADER_DEST.
#
# The template file (HEADER_TEMPLATE) will have the following tags replaced:
#   @GENERATED_CONTENT@ : The list of header includes
#                @DATE@ : The full date when the template was populated
#                @YEAR@ : The four digit year the template was populated
#
# Levi Brown
# mailto:levigroker@gmail.com
# September 8, 2017
##

UMBRELLA_STATIC_INCLUDES=${UMBRELLA_STATIC_INCLUDES:-""}

function fail()
{
    echo "Failed: $@" >&2
    exit 1
}

DEBUG=${DEBUG:-1}
export DEBUG

set -eu
[ $DEBUG -ne 0 ] && set -x

# Fully qualified binaries (_B suffix to prevent collisions)
DATE_B="/bin/date"
RM_B="/bin/rm"
AWK_B="/usr/bin/awk"
SED_B="/usr/bin/sed"
FIND_B="/usr/bin/find"
SORT_B="/usr/bin/sort"
MKTEMP_B="/usr/bin/mktemp"
BASENAME_B="/usr/bin/basename"
DIFF_B="/usr/bin/diff"
MKDIR_B="/bin/mkdir"

# The path to the resulting header file
HEADER_DEST=${HEADER_DEST:-""}
if [ "$HEADER_DEST" = "" ]; then
	fail "HEADER_DEST is required."
fi

# The path to the template to populate
HEADER_TEMPLATE=${HEADER_TEMPLATE:-""}
if [ "$HEADER_TEMPLATE" = "" ]; then
	fail "HEADER_TEMPLATE is required."
fi
if [ ! -r "$HEADER_TEMPLATE" ]; then
	fail "\"${HEADER_TEMPLATE}\" file must exist and be readable."
fi

# The directory containing the `openssl` directory which contains the header files to include
INCLUDES_DIR=${INCLUDES_DIR:-""}
if [ "$INCLUDES_DIR" = "" ]; then
	fail "INCLUDES_DIR is required."
fi

# Ensure we do not have stale generated items
$RM_B -f "${HEADER_DEST}"

DATE=$($DATE_B)
YEAR=$($DATE_B "+%Y")

# Create a temporary directory to write out our sorted includes files for comparison
BASENAME=$($BASENAME_B $0)
TEMP_DIR=$($MKTEMP_B -d "/tmp/${BASENAME}.XXXXXXXXXXXX")
$MKDIR_B -p "${TEMP_DIR}"

# Read in the static includes, sort them, and write them out to a temp file
STATIC=$(< "${UMBRELLA_STATIC_INCLUDES}")
STATIC_SORTED=$(echo "${STATIC}" | $SORT_B)
STATIC_SORTED_FILE="static"
echo "${STATIC_SORTED}" > "${TEMP_DIR}/${STATIC_SORTED_FILE}"

# Generate the list of includes from the header files in the INCLUDES_DIR, sort them, and
# write them out to a temp file.
DYNAMIC=$($FIND_B "${INCLUDES_DIR}" -name "*.h" -print | $SED_B -Ee 's|^.*/(openssl/.+\.h)$|#import <\1>|g')
DYNAMIC_SORTED=$(echo "${DYNAMIC}" | $SORT_B)
DYNAMIC_SORTED_FILE="dynamic"
echo "${DYNAMIC_SORTED}" > "${TEMP_DIR}/${DYNAMIC_SORTED_FILE}"

# NOTE: Ideally we could dynamically generate all the include statements from the headers
# found in the INCLUDES_DIR and have no need for the static includes file. Sadly that
# approach is flawed since the resulting import statements would be in lexicographical
# order, which does not satisfy internal header dependencies which ultimately makes the
# umbrella header unusable.
# Ideally we could dynamically generate the order of the imports based on a
# deterministic dependency mapping, but that's outside the scope of effort I can
# devote at this time.
# So, instead, we compare the static list with the dynamic list and alert if changes are
# needed.

# Compare the two sorted includes files with each other to determine if our static file is
# in need of update.
pushd "${TEMP_DIR}" 1> /dev/null
echo "Comparing includes from \"${UMBRELLA_STATIC_INCLUDES}\" with dynamically generated includes..."
set +e
$DIFF_B --suppress-common-lines -s "${STATIC_SORTED_FILE}" "${DYNAMIC_SORTED_FILE}"
if [ $? -ne 0 ]; then
	fail "Includes have changed. Please update \"${UMBRELLA_STATIC_INCLUDES}\" with headers from \"${INCLUDES_DIR}\""
fi
set -e
popd 1> /dev/null

# Use the static includes
CONTENT=${STATIC:-""}

# Ensure we are not writing out blank content into the template
if [ "${CONTENT}" = "" ]; then
	fail "Unexpectedly do not have content for the umbrella header."
fi

# Populate the template by replacing the @DATE@,  @YEAR@, and GENERATED_CONTENT@ tags appropriately
$AWK_B -v d="${DATE}" -v y="${YEAR}" -v cont="${CONTENT//$'\n'/\\n}" '{ gsub(/@GENERATED_CONTENT@/,cont); gsub(/@DATE@/,d); gsub(/@YEAR@/,y) }1' "${HEADER_TEMPLATE}" > "${HEADER_DEST}"
