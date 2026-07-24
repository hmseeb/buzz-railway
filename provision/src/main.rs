// Talk to the relay's owner-only endpoints with a NIP-98-signed request. Two
// jobs, both owner-signed:
//   - default: create a community via POST /operator/communities
//   - BUZZ_MINT_INVITE=1: mint a join invite via POST /api/invites and print
//     only the shareable invite URL (used to print a one-click connect link
//     at startup)
//
// Kept dependency-light: signing needs a real crypto library, but the HTTP call
// is a raw localhost request so there is no async runtime or TLS stack. The
// relay verifies the signed `u` tag against its configured public origin, not
// the socket, so we sign with the public origin and send over plain HTTP to
// 127.0.0.1.
//
// usage: buzz-provision <secret> <public-origin> <host> <owner-pubkey> <bind-port>
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::net::TcpStream;

fn sign_nip98(keys: &Keys, method: &str, url: &str, body: &[u8]) -> String {
    let payload = hex::encode(Sha256::digest(body));
    let tags = vec![
        Tag::parse(["u", url]).unwrap(),
        Tag::parse(["method", method]).unwrap(),
        Tag::parse(["nonce", &uuid::Uuid::new_v4().to_string()]).unwrap(),
        Tag::parse(["payload", &payload]).unwrap(),
    ];
    let event = EventBuilder::new(Kind::Custom(27235), "")
        .tags(tags)
        .sign_with_keys(keys)
        .expect("sign");
    B64.encode(event.as_json().as_bytes())
}

// POST a signed request to the relay over localhost. Returns (status_line, body).
//
// The request is sent to 127.0.0.1, but the Host header must be the community's
// public domain: workspace-scoped endpoints (like /api/invites) resolve the
// workspace from Host, so a localhost Host makes them 404. Server-wide endpoints
// (like /operator/communities) ignore it, so sending the real host is safe for
// both.
fn post_signed(
    keys: &Keys,
    origin: &str,
    path: &str,
    body_bytes: &[u8],
    port: u16,
) -> std::io::Result<(String, String)> {
    let host = origin
        .trim_start_matches("https://")
        .trim_start_matches("http://");
    let auth = sign_nip98(keys, "POST", &format!("{origin}{path}"), body_bytes);
    let req = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}\r\nAuthorization: Nostr {auth}\r\n\
         Content-Type: application/json\r\nContent-Length: {len}\r\nConnection: close\r\n\r\n",
        len = body_bytes.len()
    );
    let mut stream = TcpStream::connect(("127.0.0.1", port))?;
    stream.write_all(req.as_bytes())?;
    stream.write_all(body_bytes)?;
    let mut resp = String::new();
    stream.read_to_string(&mut resp).ok();
    let status = resp.lines().next().unwrap_or("").to_string();
    let body = resp.split("\r\n\r\n").nth(1).unwrap_or("").trim().to_string();
    Ok((status, body))
}

fn main() {
    let a: Vec<String> = std::env::args().collect();

    // decode mode: `buzz-provision decode npub1…` prints the 64-char hex pubkey.
    // The app shows identities as bech32 npub, but the relay wants hex, so the
    // boot script converts a deployer-supplied owner key before use.
    if a.len() >= 3 && a[1] == "decode" {
        use nostr::nips::nip19::FromBech32;
        match nostr::PublicKey::from_bech32(&a[2]) {
            Ok(pk) => {
                println!("{}", pk.to_hex());
                return;
            }
            Err(_) => {
                eprintln!("buzz-provision: not a valid npub: {}", a[2]);
                std::process::exit(1);
            }
        }
    }

    if a.len() < 6 {
        eprintln!("usage: buzz-provision <secret> <public-origin> <host> <owner-pubkey> <port>");
        std::process::exit(2);
    }
    let (secret, origin, host, owner, port_s) = (&a[1], a[2].trim_end_matches('/'), &a[3], &a[4], &a[5]);
    let port = port_s.parse::<u16>().unwrap_or(3000);
    let keys = Keys::parse(secret).expect("parse owner secret");

    let invite_mode = std::env::var("BUZZ_MINT_INVITE").is_ok();
    let path = if invite_mode { "/api/invites" } else { "/operator/communities" };
    let body = if invite_mode {
        // Long-lived so a printed link stays clickable; relay clamps to its max.
        serde_json::json!({ "ttl_secs": 604800 })
    } else {
        serde_json::json!({ "host": host, "initial_owner_pubkey": owner })
    };
    let body_bytes = serde_json::to_vec(&body).unwrap();

    // Test hook: emit the signed header and exit without touching the network.
    if std::env::var("BUZZ_PROVISION_PRINT_AUTH").is_ok() {
        println!("{}", sign_nip98(&keys, "POST", &format!("{origin}{path}"), &body_bytes));
        return;
    }

    let (status, resp_body) = match post_signed(&keys, origin, path, &body_bytes, port) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("buzz-provision: cannot reach relay on 127.0.0.1:{port}: {e}");
            std::process::exit(1);
        }
    };
    let ok = status.contains(" 200") || status.contains(" 201");

    if invite_mode {
        // Print only the invite URL so the caller can drop it straight into a
        // banner; stay silent-but-nonzero on failure.
        if ok {
            if let Some(url) = serde_json::from_str::<serde_json::Value>(&resp_body)
                .ok()
                .and_then(|v| v.get("url").and_then(|u| u.as_str()).map(String::from))
            {
                println!("{url}");
                return;
            }
        }
        eprintln!("buzz-provision: invite mint failed: {status} {resp_body}");
        std::process::exit(1);
    }

    println!("buzz-provision {host}: {status} {resp_body}");
    if !ok {
        std::process::exit(1);
    }
}
