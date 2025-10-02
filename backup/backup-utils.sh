# backup-utils.sh

# https://stackoverflow.com/questions/2990414/echo-that-outputs-to-stderr
function echoerr() {
  printf "%s\n" "$*" >&2
}

# Propagate the error condition of the last command
# Usage: propagate_error_condition
#   If the last command returned a non-zero exit code, exit the script with that code
propagate_error_condition() {
  local exit_code=$?
  if [ "$exit_code" != "0" ]; then
    exit "$exit_code"
  fi
}

# Set variable to a default value if not already set
# Usage: get_argument VAR_NAME DEFAULT_VALUE LABEL
#
# If label is not set, no message is printed.
function set_default_argument() {
  local var_name=$1
  local default_value=$2
  local label=$3

  if [ -z "${!var_name-}" ]; then
    eval "$var_name=\"$default_value\""
    [ -n "$label" ] && echo "Using default $label ${!var_name}."
  else
    [ -n "$label" ] && echo "Using override $label ${!var_name}."
  fi
}

# Create a temporary directory
# Usage: TMPDIR=$(create_tmpdir APP_NAME [PREFIX])
#   APP_NAME is used as a prefix for the temp directory name
#   PREFIX   is an optional directory where the temp dir should be created
#            If PREFIX is not provided, the system default temp directory is used
#   Returns the path to the created temp directory
create_tmpdir() {
  local app="$1"
  local prefix="$2"
  local template="${app}.XXXXXX"
  local tmpdir

  if [ -z "$app" ]; then
    echoerr "App name has not been provided!"
    exit 1
  fi

  if [ -n "$prefix" ]; then
    mkdir -p "$prefix"
    tmpdir=$(mktemp -d -p "$prefix" -t "$template")
  else
    tmpdir=$(mktemp -d -t "$template")
  fi

  if [[ ! "$tmpdir" || ! -d "$tmpdir" ]]; then
    echoerr "Could not create temporary directory!"
    exit 1
  fi

  echo "$tmpdir"
}
