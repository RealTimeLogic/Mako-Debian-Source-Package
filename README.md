# Mako Server Debian Packaging

This repo is for creating a Mako Server Debian source package that
Linux maintainers can build on their own target architectures.

https://makoserver.net/

The package build is source based. All required source code must be included
before Debian tools are run by running `download-source-package.sh`.

## Prepare the source tree

Run:

```sh
chmod +x download-source-package.sh
./download-source-package.sh
```

This creates `source-package/` with:

- `BAS/`
- `BAS-Resources/`
- `LPeg/`
- `lua-protobuf/`
- `CBOR/`
- SQLite amalgamation files in `BAS/src/`
- Debian packaging files in `debian/`

It also reads `BAS/inc/HttpServer.h` and uses `BASLIB_VER_NO` as the Debian
upstream version. For example, `#define BASLIB_VER_NO 5803` becomes package
version `5803-1`.

The script creates the matching upstream source tarball in the parent
directory, for example:

```text
mako-server_5803.orig.tar.gz
```

## Build

From inside `source-package/`, install build dependencies and build using
standard Debian tools:

```sh
sudo apt-get install build-essential devscripts debhelper zip
dpkg-buildpackage -us -uc
```

The package version is generated from `BASLIB_VER_NO` when
`download-source-package.sh` copies the Debian metadata into `source-package/`.

The Debian build invokes:

```sh
make -C BAS -f mako.mk EPOLL=TRUE PYTHON=
```

`PYTHON=` is intentional. The upstream makefile generates a random
`NewEncryptionKey.h` when Python is available, which makes package builds less
reproducible.

## Install Layout

The binary package installs:

- `/usr/bin/mako`
- `/usr/lib/mako-server/mako`
- `/usr/lib/mako-server/mako.zip`

`/usr/bin/mako` is a wrapper. The real executable and `mako.zip` are installed
together under `/usr/lib/mako-server` because the upstream runtime expects the
zip payload to be in the executable directory.

## Bundled Source Licenses

This package bundles upstream source code so Debian maintainers can build
without network access. The bundled components use the following licenses:

- `BAS`: GPL-2.0-only. See `BAS/LICENSE`.
- `BAS-Resources`: same licensing terms as BAS. See `BAS-Resources/LICENSE`.
- `LPeg`: MIT-style Lua.org/PUC-Rio license. See `LPeg/lpeg.html`.
- `lua-protobuf`: MIT. See `lua-protobuf/LICENSE`.
- `CBOR`: LGPL-3.0-or-later. See `CBOR/LICENSE` and the `LGPL3+` license field
  in `CBOR/org.conman.cbor-1.4.0-1.rockspec`.
- `SQLite amalgamation`: public domain / SQLite blessing. See the headers in
  `BAS/src/sqlite3.c`, `BAS/src/sqlite3.h`, and `BAS/src/shell.c`.
