# Cloud object-store IO: reading and writing parquet (and CSV/IPC) on S3 / GCS / Azure

## Status

Planned, not started. Research complete and verified live against the current `target/debug`
build (see "Key research findings" — every claim below was checked against the vendored crate
sources or executed, not inferred). Three phases, independently shippable in order; Phase 1 is a
three-word `Cargo.toml` change with no FFI surface at all.

## Context

`scan_parquet`/`read_parquet`/`sink_parquet` (`src/io/parquet.jl`, `c-polars/src/io.rs:117-180,
320-357`) take a path string and hand it straight to `PlRefPath::new`, which already understands
URL schemes. Upstream polars supports `s3://`, `gs://`, `az://`, `abfss://`, `http(s)://` and
`hf://` on exactly this path, gated behind Cargo features and an optional `CloudOptions` struct
that this wrapper currently hardcodes to `None` (`c-polars/src/io.rs:157` for scans;
`UnifiedSinkArgs { ..Default::default() }` at `c-polars/src/io.rs:348,487,522` for sinks).

Goal: let users read and write parquet at a remote object-store URI, with credentials supplied
either by the ambient environment or explicitly per call.

## Key research findings

These change the shape of the work substantially — the expensive-looking parts are already done.

### 1. `cloud`, `async`, `file_cache` and `http` are ALREADY enabled transitively

`cargo tree -e features -i polars-io` shows `polars-io/cloud` is reached from
`polars-plan/cloud`, `polars-stream/cloud` and `polars-mem-engine/cloud` — all pulled in by the
`lazy`/`streaming` features this crate already requests. `polars-io`'s own
`cloud = [..., "file_cache", "reqwest", "http", ...]` then cascades the rest.

This is the CLAUDE.md "per-crate feature reality is `cargo tree -e features -i <crate>`, not the
`features = [...]` list" rule paying off in the *opposite* direction for once: the feature list in
`c-polars/Cargo.toml:41` names none of these, yet they are all active.

### 2. HTTP(S) scanning already works today, with zero changes

Verified live against the current `target/debug/libpolars.so`:

```julia
julia> size(collect(scan_csv("https://raw.githubusercontent.com/pola-rs/polars/main/examples/datasets/foods1.csv")))
(27, 4)
```

Any new user-facing documentation should say so; this is not something Phase 1 enables.

### 3. The missing-provider failure mode is a clean error, NOT a process abort

This is the single most important safety finding, and it is the *opposite* of what CLAUDE.md's
standing warning about `feature_gated!` would lead you to assume. Verified live for both
directions:

```julia
scan_parquet("s3://some-bucket/some.parquet") |> collect
# PolarsError: feature 'aws' must be enabled in order to use 'Aws' cloud urls

sink_parquet(df, "s3://some-bucket/out.parquet")
# PolarsError: feature 'aws' must be enabled in order to use 'Aws' cloud urls
```

Why: `polars-io`'s `feature_gated!("cloud", …)` sites — including
`polars-plan/src/plans/conversion/dsl_to_ir/scans.rs:260,368,393,431,491,746` and
`polars-io/src/utils/file.rs:52,68` — expand to `panic!("activate 'cloud' feature")` only when
`cloud` is off. Because finding 1 means `cloud` is **on**, control reaches
`polars-io/src/cloud/object_store_setup.rs`'s `err_missing_feature`, which is a proper
`polars_bail!(ComputeError: "feature '{}' must be enabled …")` and surfaces through the existing
`polars_error()` convention.

Consequence: **there is no panic-safety work in this plan.** Phases can be exercised
incrementally without the usual "a clean build is not evidence of safety" rebuild-and-pray cycle,
and the pre-Phase-1 behaviour is already a good error message rather than a crash.

### 4. Credentials resolve from the environment with `cloud_options: None`

`PolarsObjectStoreBuilder::build_impl` (`polars-io/src/cloud/object_store_setup.rs`) does
`self.options.as_ref().unwrap_or_else(|| CloudOptions::default_static_ref())`, and
`CloudOptions::build_aws` (`polars-io/src/cloud/options.rs:354-420`) starts from
`AmazonS3Builder::from_env()` and *additionally* regex-scrapes `~/.aws/config` (region) and
`~/.aws/credentials` (`aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`). GCP and
Azure have equivalent `build_gcp`/`build_azure`.

So `AWS_ACCESS_KEY_ID` / `AWS_REGION` / `GOOGLE_SERVICE_ACCOUNT` / `AZURE_STORAGE_ACCOUNT` etc.
work with no `CloudOptions` plumbing whatsoever. That is what makes Phase 1 standalone-useful.

### 5. The dependency delta for the provider features is nearly nothing

`polars`'s `aws`/`gcp`/`azure` each expand to `["async", "cloud", "polars-io/<provider>"]`
(`polars-0.54.4/Cargo.toml:81-120,400-412`), and `polars-io`'s to `object_store/<provider>`.
`object_store-0.13.2`'s own feature table is:

```toml
aws   = ["cloud", "md-5"]
azure = ["cloud", "httparse"]
gcp   = ["cloud", "rustls-pki-types"]
http  = ["cloud"]
cloud = ["serde", "serde_json", "quick-xml", "hyper", "reqwest", "base64",
         "rand", "ring", "http-body-util", "form_urlencoded", "serde_urlencoded", "tokio"]
```

`object_store/http` is already on (finding 1), so all of `object_store/cloud` — hyper, reqwest,
ring, quick-xml, tokio — is **already compiled into the current `.so`**. Checking
`c-polars/Cargo.lock` for the three provider-specific additions: `httparse` and
`rustls-pki-types` are already present; only `md-5` is genuinely new.

The cost is therefore not new dependencies. It is that any change to the feature set invalidates
the whole graph and forces the full opt-level-3 rebuild — which per CLAUDE.md's OOM incident must
run at **`-j 1`**, not the usual `-j 4`.

### 6. `CloudScheme::from_path` is public, so Julia never needs to name the provider

`CloudOptions::from_untyped_config(scheme: Option<CloudScheme>, config)`
(`polars-io/src/cloud/options.rs:652`) needs a `CloudScheme` to know which key namespace to parse
against, but `CloudScheme::from_path(&str) -> Option<Self>`
(`polars-utils/src/pl_path.rs:397-408`) derives it from the URI. Recognised schemes: `abfs`,
`abfss`, `adl`, `az`, `azure`, `file`, `gcs`, `gs`, `hf`, `http`, `https`, `s3`, `s3a`.

This is what makes the Phase 2 handle design below work: the handle can hold raw key/value pairs
and defer scheme resolution to the call site, where the path is known.

### 7. Unknown option keys already error cleanly

`from_untyped_config` dispatches to `parse_untyped_config::<AmazonS3ConfigKey, _>` etc., which
returns `Err` on an unrecognised key, and bails with `"'aws' feature is not enabled"` for a
provider whose feature is off. No extra validation layer is needed on the Julia side.

## Phase 1 — enable the provider features (no FFI, no Julia changes)

Add three strings to the `polars` dependency's feature list at `c-polars/Cargo.toml:41`:

```toml
"aws", "gcp", "azure",
```

Nothing else changes. No Rust, no `c-polars/include/polars.h`, no `src/api/generated.jl`
regeneration, no Julia signature changes: `scan_parquet`/`read_parquet`/`sink_parquet` already
forward the path string to `PlRefPath::new`, and `scan_csv`/`scan_ipc`/`sink_csv`/`sink_ipc` get
the same capability for free.

Add a comment above the feature list in the style of the existing `dtype-time`/`meta` notes,
recording finding 1 (that `cloud`/`async`/`file_cache`/`http` arrive transitively and only the
three provider features are missing) — otherwise a future reader will "helpfully" add `cloud` and
`http` to the list and not know why they were omitted.

**Build:** `cd c-polars && cargo build -j 1`. This is a feature change, so it is a full
from-scratch optimized rebuild of every vendored crate — the exact scenario that OOM-killed the
VS Code host at `-j 4`. Expect it to be slow. Restart any live Julia session afterwards (the `.so`
is already mapped in).

**Verify:** the two commands from finding 3 must stop returning `feature 'aws' must be enabled`
and start returning a real credential/network error (e.g. an S3 403/404), proving the provider
code path is now compiled in.

After this phase, S3/GCS/Azure read and write work for anyone whose credentials are in the
environment or in `~/.aws/*`.

## Phase 2 — explicit `storage_options` via a `polars_cloud_options_t` handle

Needed for: MinIO / Cloudflare R2 / any custom `aws_endpoint_url`, per-call credentials,
non-default region, anonymous/unsigned access, and (as a side effect) local integration testing.

### Design decision: an opaque handle, not per-call key/value array parameters

The alternative — appending `keys`, `key_lens`, `values`, `value_lens`, `n` to each function —
would touch six call sites (`scan_parquet`, `scan_csv`, `scan_ipc`, `sink_parquet`, `sink_csv`,
`sink_ipc`), adding five parameters each. `polars_lazy_frame_scan_csv` already takes 27 arguments
and `polars_lazy_frame_sink_csv` already carries `#[allow(clippy::too_many_arguments)]`. One new
handle type, constructed once and passed as a single nullable pointer, is both smaller and
reusable across all six.

**Deviation from the usual convention, deliberately:** every other opaque handle in this package
wraps a real polars type. `polars_cloud_options_t` instead wraps
`Vec<(PlSmallStr, String)>` — the *unparsed* key/value pairs — because `CloudOptions` cannot be
built without knowing the scheme (finding 6), and the scheme comes from the path, which is only
known at the call site. Resolution therefore happens per call:

```rust
CloudOptions::from_untyped_config(CloudScheme::from_path(path), pairs.iter().cloned())
```

Document this reasoning in a doc comment on the struct, since it reads as an inconsistency
otherwise. The handle is otherwise conventional: `Box::into_raw`/`Box::from_raw`, a
`polars_cloud_options_destroy`, a Julia `mutable struct` with a `finalizer` and an
`unsafe_convert` method.

### Rust (`c-polars/src/io.rs`, plus the handle type)

- `polars_cloud_options_new(keys, key_lens, values, value_lens, n, out) -> *const polars_error_t`
  — parallel arrays of `(ptr, len)` pairs, following the existing string convention. Validate
  UTF-8 via the existing `read_str`.
- `polars_cloud_options_destroy(ptr)`.
- Thread a nullable `cloud_options: *const polars_cloud_options_t` parameter into all six
  scan/sink functions. `null` preserves today's behaviour exactly (`None` → environment
  fallback), so this is not a breaking change to the C ABI's semantics, only its signatures.
- Scans set `ScanArgsParquet.cloud_options: Option<CloudOptions>`
  (`c-polars/src/io.rs:157`) / `UnifiedScanArgs.cloud_options` for CSV and IPC.
- Sinks set `UnifiedSinkArgs.cloud_options: Option<Arc<CloudOptions>>`
  (`polars-plan/src/dsl/options/sink.rs:37`), replacing the current bare `..Default::default()`.
- All of this stays inside the existing `guard_error` closures; `from_untyped_config` returns
  `PolarsResult`, so it composes with `tri!` directly.

### Header + bindings

Hand-add the prototypes and the `polars_cloud_options_t` opaque struct to
`c-polars/include/polars.h` in cbindgen style, run `python3 c-polars/check_header_drift.py`, then
regenerate with `julia --project=gen gen/generate.jl` and `runic -i src/api/generated.jl`.

### Julia

Add a `storage_options::Union{Nothing,AbstractDict{<:AbstractString,<:AbstractString}} = nothing`
keyword to `scan_parquet`/`read_parquet`/`sink_parquet` (and the CSV/IPC equivalents), marshalled
under `GC.@preserve` into the pointer arrays. Keys pass through verbatim to polars — do not
maintain a Julia-side allowlist, since finding 7 shows upstream already rejects unknown keys with
a good message, and an allowlist would silently rot against upstream.

Remember `ncodeunits`, never `length`, for every key and value (CLAUDE.md's 24-site bug; secret
keys and endpoint URLs are exactly the kind of value that can be non-ASCII).

## Phase 3 — close the eager `write_*` gap

`write_parquet(p::String, df)` is `open(io -> write_parquet(io, df; kwargs...), p, "w")`
(`src/io/parquet.jl:140`), i.e. pure Julia local file IO through the `IOCallback` bridge — the
Rust side never sees the path. Same for `write_csv` (`src/io/csv.jl:202`) and `write_ipc`
(`src/io/ipc.jl:108`). So after Phase 1, `write_parquet("s3://bucket/out.parquet", df)` silently
creates a **local file literally named `s3:/bucket/out.parquet`** rather than erroring or
uploading. That is the worst failure mode in this whole plan and the only genuinely new bug Phase
1 introduces.

Two options:

1. **Route scheme-bearing paths to the sink.** In the `::String` methods, check
   `occursin("://", p)` (or a small scheme predicate mirroring `CloudScheme::from_path`) and
   delegate to `sink_parquet(lazy(df), p; …)`. Transparent for users; the wrinkle is that the
   eager and sink option sets are not identical (`sink_*` additionally has `mkdir`/
   `maintain_order`, and `write_csv` vs `sink_csv` differ on compression — see
   `plans/csv_ipc_io_options.md`), so the delegation has to be explicit about which keywords it
   forwards rather than splatting `kwargs...` blindly.
2. **Error with a pointer.** Detect the scheme and throw
   `"write_* writes local files; use sink_* for cloud URIs"`.

Recommend option 1 for parquet (the format users will actually want this for) and option 2 as the
minimum bar for CSV/IPC if the option-set mismatch makes delegation awkward. Either way, do not
leave the silent-local-file behaviour in place.

## Testing

`test/lazyframe/scan_parquet.jl` and `test/lazyframe/sink_parquet.jl` are the homes for these,
matching the existing per-concern layout.

- **Phase 1, no credentials needed:** assert that an `s3://` URI now produces an error whose
  message is *not* `"feature 'aws' must be enabled"`. Cheap, hermetic, and directly regression-
  guards the feature flags — if someone trims the feature list later, this fails.
- **HTTP path (works today):** a `scan_csv`/`scan_parquet` over an `https://` URL is a real
  end-to-end cloud-IO test, but it needs network access. Gate it behind an env var
  (e.g. `POLARS_JL_NETWORK_TESTS=1`) so `Tests.yml` and offline runs skip it.
- **Phase 2, real round-trip:** MinIO on localhost, driven via `storage_options` with
  `aws_endpoint_url`, `aws_access_key_id`, `aws_secret_access_key`, `aws_region`,
  `aws_allow_http=true`. Note the ordering dependency: **this test is only expressible after
  Phase 2**, because pointing at a non-AWS endpoint requires exactly the explicit-options plumbing
  Phase 2 adds. Phase 1 alone is not round-trip-testable without real cloud credentials.
- **Phase 3:** assert `write_parquet("s3://…", df)` does not create a local file — a plain
  `isfile`/`isdir` check on the tempdir after the call catches the silent-local-file regression
  without needing any network.

Run the suite the CLAUDE.md way: a scratch environment with `Pkg.develop(path=".")` plus
`Aqua`/`Test`/`Tables`/`TimeZones`, then
`JULIA_PROJECT=<scratch> julia -e 'include("test/runtests.jl")'`.

## Risks and open questions

- **The `-j 1` rebuild is the main cost of Phase 1** and it is a real one, not a formality. Budget
  for it and do not start it alongside other memory pressure.
- **Distribution.** `gen/prologue.jl` prefers a local `target/{release,debug}` build but otherwise
  loads registered `libpolars_jll`. None of this reaches users on the JLL until it is rebuilt with
  the new features. Confirm whether rebuilding/publishing the JLL is in scope before Phase 1 —
  if it is not, Phase 1 benefits only people building `c-polars` themselves, which changes how
  much Phase 2/3 polish is worth.
- **Binary size.** The dev `.so` is already ~240 MB (finding 5 means most of the object-store
  stack is in there already), but the provider code paths will add some. Worth measuring after
  Phase 1 if JLL size matters for distribution.
- **`file_cache`.** Already enabled, so polars will cache remote files and honour
  `POLARS_FILE_CACHE_TTL`. This is existing behaviour that becomes user-visible in Phase 1 —
  mention it in the docs rather than trying to expose `CloudOptions.file_cache_ttl` as a keyword.
- **Concurrency.** Cloud IO runs on polars' own tokio runtime (`polars_core::runtime::ASYNC`),
  independent of `JULIA_NUM_THREADS`. Nothing in `docs/src/limitations.md`'s "Concurrency" note
  needs to change — handles remain non-shareable across Julia tasks exactly as before — but the
  cloud docs should not imply otherwise.

## Out of scope

- **Credential providers** (`CloudOptions::with_credential_provider` /
  `PlCredentialProvider`) — an upstream hook designed around a Python callable, for refreshing
  short-lived credentials. A Julia-callback equivalent would need the `IOCallback` treatment and
  is a separate piece of work; the `~/.aws/credentials` + env-var path covers ordinary use.
- **Retry tuning** (`CloudOptions::with_retry_config` / `CloudRetryConfig`'s `max_retries`,
  `retry_timeout`, backoff knobs) — a natural Phase 2 follow-on riding the same handle, but
  defaults are sane and it is not needed for the core capability.
- **`hf://` (Hugging Face)** — works via the `http` feature already enabled, but has its own token
  resolution path in `from_untyped_config`; untested and undocumented here.
- **Partitioned sinks** (`SinkDestination::Partitioned`) — this wrapper only uses
  `SinkDestination::File` today. Writing a Hive-partitioned dataset to a cloud prefix is a
  distinct capability, orthogonal to cloud support, and deserves its own plan.
- **`scan_csv` hive partitioning** — still blocked upstream by `LazyCsvReader`'s hardcoded
  `HiveOptions::new_disabled()` (see CLAUDE.md's "Known sharp edges"); unchanged by any of this.
