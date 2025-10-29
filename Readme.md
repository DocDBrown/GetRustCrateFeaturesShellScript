# Shell Script to check crates.io features

example usage "./crates-features.sh serde tokio anyhow tracing"

## Created so you can check what features there are for the crates you need

1. Create a shell script that accepts crate names as input, fetches each crate’s newest version from the crates.io API, retrieves that version’s metadata, and prints the crate name if the features map is non-empty
2. /api/v1/crates/{name}/versions returns version objects that include a features map. Non-empty ⇒ activatable features.
3. The per-crate endpoint exposes the newest version number, which you can query directly. If absent, list versions and pick the first
4. Handle HTTP errors and timeouts. crates.io enforces polite crawling
5. If max_version empty, call /api/v1/crates/${crate_name}/versions and pick the first non-yanked version’s .num.
6. Ensure delay is not too short for crates.io’s crawler policy.
