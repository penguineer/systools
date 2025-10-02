# backup-utils.sh

# https://stackoverflow.com/questions/2990414/echo-that-outputs-to-stderr
function echoerr() {
  printf "%s\n" "$*" >&2
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
