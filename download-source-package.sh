#!/usr/bin/env bash
set -euo pipefail

# Download or update the source repositories used by BAS/LinuxBuild.sh, fetch
# the SQLite amalgamation into BAS/src, then create source-package/ without
# repository metadata.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="${SCRIPT_DIR}/source-package"

REPOS=(
  "BAS|https://github.com/RealTimeLogic/BAS.git"
  "BAS-Resources|https://github.com/RealTimeLogic/BAS-Resources.git"
  "LPeg|https://github.com/roberto-ieru/LPeg.git"
  "lua-protobuf|https://github.com/starwing/lua-protobuf.git"
  "CBOR|https://github.com/spc476/CBOR.git"
)

abort() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || abort "Missing required command: $1"
}

clone_or_update() {
  local dir="$1"
  local url="$2"

  if [[ -d "$dir/.git" ]]; then
    printf 'Updating %s\n' "$dir"
    git -C "$dir" pull --ff-only
  elif [[ -e "$dir" ]]; then
    abort "'$dir' already exists but is not a Git repository"
  else
    printf 'Cloning %s\n' "$dir"
    git clone "$url" "$dir"
  fi
}

download_sqlite_amalgamation() {
  local html product_line product version relative_url size sha url archive tmpdir extracted_dir

  if [[ -n "${SQLITEURL:-}" ]]; then
    url="$SQLITEURL"
  else
    printf 'Fetching latest SQLite amalgamation metadata\n'
    html="$(curl -fsSL https://sqlite.org/download.html)"
    product_line="$(
      printf '%s\n' "$html" |
        grep -E 'PRODUCT,[0-9.]+,[0-9]{4}/sqlite-amalgamation-[0-9]+\.zip,' |
        head -n 1 ||
        true
    )"
    [[ -n "$product_line" ]] || abort "Could not determine latest SQLite amalgamation URL"

    IFS=',' read -r product version relative_url size sha <<<"$product_line"
    url="https://sqlite.org/${relative_url}"
  fi

  archive="${url##*/}"
  tmpdir="$(mktemp -d)"

  printf 'Downloading SQLite amalgamation: %s\n' "$url"
  curl -fL "$url" -o "${tmpdir}/${archive}"

  unzip -q -o "${tmpdir}/${archive}" -d "$tmpdir"
  extracted_dir="$(
    find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -name 'sqlite-amalgamation-*' |
      head -n 1
  )"
  [[ -n "$extracted_dir" ]] || abort "Downloaded SQLite archive did not contain sqlite-amalgamation-*"

  mkdir -p BAS/src
  cp "${extracted_dir}"/* BAS/src/
  rm -rf "$tmpdir"

  printf 'Placed SQLite amalgamation in BAS/src\n'
}

copy_without_git() {
  local dir="$1"
  local target="${PACKAGE_DIR}/${dir}"

  printf 'Copying %s to source-package/%s\n' "$dir" "$dir"
  mkdir -p "$target"
  (
    cd "$dir"
    tar --exclude='./.git' --exclude='.git' --exclude='*/.git' -cf - .
  ) | (
    cd "$target"
    tar -xf -
  )
}

copy_packaging_metadata() {
  printf 'Copying Debian packaging metadata\n'
  cp -R debian "$PACKAGE_DIR/"
  cp README.md "$PACKAGE_DIR/PACKAGING.md"
  find "$PACKAGE_DIR/debian" -type f -exec chmod 0644 {} +
  chmod 0755 "$PACKAGE_DIR/debian/rules"
  chmod 0755 "$PACKAGE_DIR/debian/mako"
}

remove_generated_artifacts() {
  printf 'Removing generated build artifacts from source-package\n'
  rm -rf "$PACKAGE_DIR/BAS-Resources/build/MakoBuild"
  rm -f "$PACKAGE_DIR/BAS-Resources/build/mako.zip"
  rm -f "$PACKAGE_DIR/BAS/mako"
  rm -f "$PACKAGE_DIR/BAS/mako.zip"
  rm -f "$PACKAGE_DIR/BAS"/*.o
  rm -f "$PACKAGE_DIR/BAS/examples/MakoServer/src/NewEncryptionKey.h"
}

bas_package_version() {
  local bas_version

  bas_version="$(
    sed -n 's/^#define[[:space:]]\+BASLIB_VER_NO[[:space:]]\+\([0-9][0-9]*\).*/\1/p' \
      BAS/inc/HttpServer.h |
      head -n 1
  )"
  [[ -n "$bas_version" ]] || abort "Could not determine BASLIB_VER_NO from BAS/inc/HttpServer.h"

  printf '%s-1\n' "$bas_version"
}

update_debian_changelog_version() {
  local package_version

  package_version="$(bas_package_version)"
  printf 'Setting Debian package version: %s\n' "$package_version"
  sed -i "1s/^mako-server ([^)]*)/mako-server (${package_version})/" \
    "$PACKAGE_DIR/debian/changelog"
}

create_orig_tarball() {
  local package_version upstream_version orig_tarball

  package_version="$(
    sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "${PACKAGE_DIR}/debian/changelog"
  )"
  [[ -n "$package_version" ]] || abort "Could not determine package version from debian/changelog"

  upstream_version="${package_version%-*}"
  orig_tarball="${SCRIPT_DIR}/mako-server_${upstream_version}.orig.tar.gz"

  printf 'Creating upstream source tarball: %s\n' "${orig_tarball##*/}"
  (
    cd "$PACKAGE_DIR"
    tar --exclude='./debian' \
      --transform "s,^\.,mako-server-${upstream_version}," \
      -czf "$orig_tarball" .
  )
}

main() {
  require_command git
  require_command curl
  require_command find
  require_command mktemp
  require_command unzip
  require_command tar

  cd "$SCRIPT_DIR"

  for repo in "${REPOS[@]}"; do
    IFS='|' read -r dir url <<<"$repo"
    clone_or_update "$dir" "$url"
  done

  download_sqlite_amalgamation

  if [[ -d "BAS-Resources/build" ]]; then
    shopt -s nullglob
    build_scripts=(BAS-Resources/build/*.sh)
    if ((${#build_scripts[@]})); then
      chmod +x "${build_scripts[@]}"
    fi
    shopt -u nullglob
  fi

  rm -rf "$PACKAGE_DIR"
  mkdir -p "$PACKAGE_DIR"

  for repo in "${REPOS[@]}"; do
    IFS='|' read -r dir _ <<<"$repo"
    copy_without_git "$dir"
  done

  remove_generated_artifacts
  copy_packaging_metadata
  update_debian_changelog_version
  create_orig_tarball

  printf 'Done: %s\n' "$PACKAGE_DIR"
}

main "$@"
