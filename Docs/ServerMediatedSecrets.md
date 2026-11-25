# Server-mediated secrets

Classify privileged credentials as `serverOnly`. The compiler skips these keys and fails
validation or sealing if `--required-keys` or `SECRETS_REQUIRED_KEYS` explicitly selects one.
This keeps the values out of `Secrets.sealed`. SecretsKit provides build-time enforcement.
A token exchange and reference backend are deferred.

## Backend and client responsibilities

Keep the upstream credential on your backend. The app can call that backend to perform the
privileged operation, or the backend can issue a short-lived, scoped token if the upstream
service supports it. Authorize each operation or token request, enforce expiration, and
support revocation. If the credential lives in Vault, give the backend access separately
from the build's Vault policy.

If you use App Attest, verify the attestation and subsequent assertions on the server.
Check `DCAppAttestService.isSupported` and define how the app and server handle unsupported
devices. Apple documents support for watchOS extensions on watchOS 9 or later.
[App Attest availability](https://developer.apple.com/documentation/devicecheck/dcappattestservice/issupported) ·
[Server-side validation](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server)

Keep any issued token in memory, refresh it after expiration, and handle exchange failure
through the normal client error path. [Security notes](SecurityNotes.md)
