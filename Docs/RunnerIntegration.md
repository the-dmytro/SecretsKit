# Runner integration

Copy the [runner and wrappers](../IntegrationTemplates/README.md) into the consumer project so
Xcode can call them from a stable path outside DerivedData. The runner defaults to
`Config/SecretsKit.config.json`. Set `SECRETS_CONFIG_PATH` to use a different file.

## Provision the compiler

Build the CLI from a trusted SecretsKit checkout on macOS with Swift 5.9 or later.

```sh
swift build -c release --product secretcompiler
```

The binary is at `$(swift build -c release --show-bin-path)/secretcompiler`. Supply its absolute
path and the SHA-256 from your approved build to the consumer's build environment.

```sh
export SECRETSKIT_CLI_PATH="/absolute/path/to/secretcompiler"
export SECRETSKIT_CLI_SHA256="<approved SHA-256>"
```

For a source-built cache, run `./Scripts/SecretsKit/secretskit.sh install` from the consumer
project root before supplying secrets. With `strict` or `locked`, the runner uses
`SECRETSKIT_CLI_REF` if set, otherwise it looks for an Xcode `Package.resolved` and prefers the
SecretsKit revision in that file. Supply the same ref to install and the build phases if you
set it explicitly. The default cache is `.tools/secretskit/<ref>/secretcompiler`. When install
builds without a digest, establish the approved digest before using the cache for
`validate` or `seal`.

## Compiler selection and policy

The runner checks an executable at `SECRETSKIT_CLI_PATH` first, then `secretcompiler` on `PATH`,
then a cached compiler for the selected ref. Choose a policy with `cli.policy` in the config or
override it with `SECRETSKIT_CLI_POLICY`.

- `strict` is the default, and `locked` uses the same checks. A selected compiler needs a
  matching digest for secret-processing commands. A verified compiler at an explicit path or
  on `PATH` can run without a source ref. The source build checks the checked-out commit when
  the selected ref is a full commit SHA.
- `compatible` accepts path and cached binaries without the strict digest requirement.
  Source lookup uses `SECRETSKIT_CLI_REF` or `SECRETSKIT_CLI_REF_FALLBACK`. Only `install`
  falls back to `main` when neither is set. Supply a commit SHA for a reproducible source build.

Set `SECRETSKIT_AUTO_BOOTSTRAP=1` to allow a source build during `seal` or `validate`. This
requires a resolvable ref, and strict or locked policy also requires an approved digest before
building. The runner checks that digest before using the resulting binary.

For Xcode build phases, pass compiler settings through the build environment or wrappers.
For CI, provision the compiler before injecting plaintext inputs. [Xcode setup](XcodeIntegration.md)
· [CI setup](CI.md)
