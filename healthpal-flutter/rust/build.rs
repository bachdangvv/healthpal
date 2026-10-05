use std::fs;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

fn sha256_file(path: &Path) -> String {
    let mut hasher = Sha256::new();
    hasher.update(
        fs::read(path).unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display())),
    );
    hex_encode(&hasher.finalize())
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

fn read_json_object(path: &Path) -> serde_json::Map<String, serde_json::Value> {
    let text = fs::read_to_string(path)
        .unwrap_or_else(|err| panic!("failed to read {}: {err}", path.display()));
    serde_json::from_str(&text)
        .unwrap_or_else(|err| panic!("failed to parse {}: {err}", path.display()))
}

fn require_hash(assets: &Path, manifest: &serde_json::Map<String, serde_json::Value>, name: &str) {
    let path = assets.join(name);
    let actual = sha256_file(&path);
    let expected = manifest
        .get(name)
        .and_then(serde_json::Value::as_str)
        .unwrap_or_else(|| panic!("checksum manifest is missing {name}"));
    if actual != expected {
        panic!("SHA-256 mismatch for {name}: {actual} != {expected}");
    }
}

fn main() {
    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let assets = manifest_dir.join("assets").join("healthpal_fatigue_v4");
    println!("cargo:rerun-if-changed={}", assets.display());

    let source_manifest = read_json_object(&assets.join("artifact_checksums.sha256.json"));
    require_hash(&assets, &source_manifest, "healthpal_fatigue_v4.onnx");
    require_hash(
        &assets,
        &source_manifest,
        "healthpal_fatigue_v4_config.json",
    );

    let mobile_manifest = read_json_object(&assets.join("mobile_artifact_checksums.sha256.json"));
    require_hash(
        &assets,
        &mobile_manifest,
        "healthpal_fatigue_v4_mobile.onnx",
    );
    require_hash(
        &assets,
        &mobile_manifest,
        "healthpal_fatigue_v4_mobile_weights.json",
    );
}
