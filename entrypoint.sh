#!/bin/bash
set -e
umask 002

USERNAME="${USERNAME:-opencode}"

validate_required_vars() {
  if [ -z "$HOST_UID" ]; then
    echo "ERROR: HOST_UID environment variable is required"
    exit 1
  fi
  if [ -z "$HOST_GID" ]; then
    echo "ERROR: HOST_GID environment variable is required"
    exit 1
  fi
}

# Helpers replacing getent (not available on Alpine/musl)
_group_by_gid() { awk -F: -v gid="$1" '$3 == gid {print $1; exit}' /etc/group; }
_gid_exists()   { grep -q "^[^:]*:[^:]*:${1}:" /etc/group; }
_name_in_group() { grep -q "^${1}:" /etc/group; }
_user_by_uid()  { awk -F: -v uid="$1" '$3 == uid {print $1; exit}' /etc/passwd; }
_home_by_uid()  { awk -F: -v uid="$1" '$3 == uid {print $6; exit}' /etc/passwd; }

setup_user() {
  local username="$1"

  # Create group for HOST_GID if it doesn't exist
  if ! _gid_exists "$HOST_GID"; then
    local group_name="$username"
    _name_in_group "$username" && group_name="user-host"
    groupadd -g "$HOST_GID" "$group_name"
    echo "Group '${group_name}' created with GID ${HOST_GID}"
  fi

  # Create group for DOCKER_GID if it doesn't exist
  if [ -n "$DOCKER_GID" ] && [ "$DOCKER_GID" != "$HOST_GID" ] && ! _gid_exists "$DOCKER_GID"; then
    groupadd -g "$DOCKER_GID" docker-host
    echo "Group 'docker-host' created with GID ${DOCKER_GID}"
  fi

  # Check if a user with HOST_UID already exists
  local existing_user
  existing_user=$(_user_by_uid "$HOST_UID")

  if [ -n "$existing_user" ]; then
    local existing_home
    existing_home=$(_home_by_uid "$HOST_UID")

    pkill -u "$existing_user" 2>/dev/null || true

    if [ "$existing_user" != "$username" ]; then
      usermod -l "$username" "$existing_user"
      echo "Renamed user from '${existing_user}' to '${username}'"
    fi

    local target_home="/home/${username}"
    if [ "$existing_home" != "$target_home" ]; then
      usermod -d "$target_home" -m "$username" 2>/dev/null || usermod -d "$target_home" "$username"
      echo "Changed home directory to ${target_home}"
    fi
  else
    useradd -u "$HOST_UID" -g "$HOST_GID" -d "/home/${username}" -m -s /bin/bash "$username"
    echo "User '${username}' created with UID ${HOST_UID}"
  fi

  # Ensure membership in primary group
  local primary_group
  primary_group=$(_group_by_gid "$HOST_GID")
  if [ -n "$primary_group" ]; then
    usermod -aG "$primary_group" "$username"
    echo "Added '${username}' to group '${primary_group}'"
  fi

  # Ensure membership in docker group
  if [ -n "$DOCKER_GID" ]; then
    local docker_group
    docker_group=$(_group_by_gid "$DOCKER_GID")
    if [ -n "$docker_group" ]; then
      usermod -aG "$docker_group" "$username"
      echo "Added '${username}' to group '${docker_group}'"
    fi
  fi
}

setup_shell() {
  local user="$1"
  local bashrc="/home/${user}/.bashrc"

  mkdir -p "/home/${user}"
  chown "${user}:${HOST_GID}" "/home/${user}" 2>/dev/null || true

  local profile="/home/${user}/.profile"
  if ! grep -q '\.bashrc' "$profile" 2>/dev/null; then
    echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> "$profile"
  fi

  {
    echo "PS1='\\[\\e[38;5;5m\\]\\[\\e[1m\\](${user})\\[\\e[m\\] \\[\\e[34m\\]\\[\\e[1m\\]\\W\\[\\e[m\\] \\$ \\033[0m'"
    echo "alias ll='ls -al'"
    echo "alias la='ls -la'"
    echo "alias l='ls -cf'"
    echo "alias ..='cd ..'"
    echo "alias ...='cd ../..'"
    echo "export PATH=\$HOME/.local/bin:\$PATH"
  } > "$bashrc"

  echo "Shell configuration written to ${bashrc}"
}

main() {
  validate_required_vars

  echo "Setting up user: ${USERNAME} (UID: ${HOST_UID}, GID: ${HOST_GID})"

  setup_user "$USERNAME"
  setup_shell "$USERNAME"

  if [ $# -eq 0 ]; then
    echo "Starting interactive shell for user: ${USERNAME}"
    exec su -l "$USERNAME" -s /bin/bash
  else
    echo "Executing command as user ${USERNAME}: $*"
    exec su -l "$USERNAME" -s /bin/bash -c "
      cd $PWD || exit 1
      export PATH=~/.local/bin:$PATH
      exec $*
    "
  fi
}

main "$@"
