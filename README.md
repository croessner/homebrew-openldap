# Homebrew OpenLDAP with SSHA512 and optional Argon2id

macOS tap for OpenLDAP, maintained by Christian Rößner. The only formula is
[`openldap.rb`](openldap.rb). It builds the SHA-2 password module and Argon2id
support in addition to the overlays provided by Homebrew core.

## Install

```sh
brew tap croessner/openldap
brew install --build-from-source croessner/openldap/openldap
```

If Homebrew core's OpenLDAP is already installed, first back up its configuration,
data and binary package, stop the service, and replace it with:

```sh
brew reinstall --build-from-source croessner/openldap/openldap
brew test croessner/openldap/openldap
```

The fully qualified name matters. The executable paths remain under
`$(brew --prefix)/opt/openldap`, so an existing LaunchAgent can keep using them.
This tap builds from source; it does not currently publish bottles.

## Password policy

Include the following **before all `database` directives** in `slapd.conf`:

```text
include /usr/local/opt/openldap/share/openldap/password-modules.conf
```

On Apple Silicon replace `/usr/local` with `/opt/homebrew`. The fragment loads
`pw-sha2` and `argon2`, then sets **`password-hash {SSHA512}`**. Existing configuration
is deliberately preserved during installation and upgrades. Include this fragment
once; remove conflicting duplicate module or password-hash directives first.

SSHA512 is the server default for RFC 3062 Password Modify operations. Existing
SSHA512 hashes work unchanged. Argon2id is available for verification and explicit
hash generation, but **is not the default**. No stored passwords are automatically
converted. Argon2 verification incurs its configured CPU and memory costs only for
accounts with an Argon2 hash.

```sh
# Prompts for a password; does not put the password into shell history.
"$(brew --prefix openldap)/sbin/slappasswd" \
  -o module-path="$(brew --prefix openldap)/libexec/openldap" \
  -o module-load=pw-sha2 -h '{SSHA512}'

# Optional Argon2id generation; leaves the server default unchanged.
"$(brew --prefix openldap)/sbin/slappasswd" \
  -o module-path="$(brew --prefix openldap)/libexec/openldap" \
  -o module-load=argon2 -h '{ARGON2}'
```

The CLI `slappasswd` does not read server configuration: pass its module and scheme
explicitly. The installed SHA-2 module also provides SHA256/SHA384/SHA512 and their
salted forms. Password verification is performed by LDAP, not by this tap.

## Service and upgrades

A service definition is supplied for `brew services start croessner/openldap/openldap`.
It uses the existing `etc/openldap/slapd.conf`, loopback LDAP port 1389,
loopback LDAPS port 1636 and the default LDAPI socket. Configure certificates
before using LDAPS. Do not run it alongside a separate existing slapd LaunchAgent.
No service is started automatically by installation.

OpenLDAP 2.7 uses LMDB 1.0 and cannot open a 2.6-format MDB database directly.
Export with OpenLDAP 2.6 `slapcat`, then import into a fresh directory with 2.7
`slapadd`. Keep an original backup and compare entries/attributes before switching.
Upgrades within this tap never migrate database files automatically.

## Validation and automated updates

`brew test croessner/openldap/openldap` starts a disposable Unix-socket-only LDAP
server. It verifies SSHA512 and Argon2id password binds, RFC 3062 changes generating
SSHA512, rejection of the old password, and SASL EXTERNAL. It does not connect to
an existing LDAP server. CI builds and tests Intel and Apple Silicon macOS.

A daily workflow follows the official **Feature Release** marker, validates the
published SHA3-512 checksum and opens/updates one version PR with the SHA-256 pin.
Unexpected checksum changes for the same version fail rather than being blessed.
PRs are assigned to `croessner`; no automatic merge is enabled. The workflow
explicitly dispatches CI for bot-created PRs, which otherwise would not trigger
builds with `GITHUB_TOKEN`. Repository settings must allow Actions to create PRs.
Use GitHub Watch → All Activity to receive repository events.

Based on the Homebrew core OpenLDAP formula. Tap code is BSD-2-Clause; OpenLDAP
retains its OLDAP-2.8 license. See [LICENSE](LICENSE).
