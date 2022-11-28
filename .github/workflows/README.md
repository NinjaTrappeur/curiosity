# GitHub Actions CI

On top of building and testing the curiosity codebase, this CI pipeline is also in charge of populating the Nix binary cache.

We currently store this binary cache in a Backblaze B2 bucket.

This pipeline is relying on some [GitHub actions secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets):

- `NIX_PUB_KEY` and `NIX_SIGNING_KEY`: respectively the public and private key used to sign the binary cache NARs. You can generate such a key using `nix-store --generate-binary-cache-key curiosity-store cache-priv-key.pem cache-pub-key.pem`.
- `B2_APPKEY_ID` and `B2_APPKEY`: respectively the B2 bucket key id and the associated private key.
