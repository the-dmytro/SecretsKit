# Security Notes

- Secrets embedded in an app bundle can be extracted by a determined attacker.
- This system raises effort via obfuscation but does not make secrets fully safe.
- Only embed keys that are safe to ship (e.g., publishable keys), and use server-issued tokens for sensitive credentials.
- The sealed resource is intended to avoid plaintext intermediates in DerivedData or the repo.
