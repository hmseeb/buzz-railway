// Create a Buzz community by calling the relay's operator endpoint with a
// NIP-98-signed request. Kept dependency-light: signing needs a real crypto
// library, but the HTTP call is a raw localhost request so there is no async
// runtime or TLS stack to pull in.
//
// The relay verifies the signed `u` tag against its configured public origin,
// not the socket it received the request on, so we sign with the public origin
// and send over plain HTTP to 127.0.0.1.
//
// usage: buzz-provision <secret> <public-origin> <host> <owner-pubkey> <bind-port>
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::net::TcpStream;

const PATH: &str = "/operator/communities";

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

fn main() {
    let a: Vec<String> = std::env::args().collect();
    if a.len() < 6 {
        eprintln!("usage: buzz-provision <secret> <public-origin> <host> <owner-pubkey> <port>");
        std::process::exit(2);
    }
    let (secret, origin, host, owner, port) = (&a[1], a[2].trim_end_matches('/'), &a[3], &a[4], &a[5]);

    let keys = Keys::parse(secret).expect("parse owner secret");
    let sign_url = format!("{origin}{PATH}");
    let body = serde_json::json!({ "host": host, "initial_owner_pubkey": owner });
    let body_bytes = serde_json::to_vec(&body).unwrap();
    let auth = sign_nip98(&keys, "POST", &sign_url, &body_bytes);

    // Test hook: emit the signed header and exit without touching the network,
    // so the boot test can check the signing path without a live relay.
    if std::env::var("BUZZ_PROVISION_PRINT_AUTH").is_ok() {
        println!("{auth}");
        return;
    }

    let req = format!(
        "POST {PATH} HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Nostr {auth}\r\n\
         Content-Type: application/json\r\nContent-Length: {len}\r\nConnection: close\r\n\r\n",
        len = body_bytes.len()
    );

    let mut stream = match TcpStream::connect(("127.0.0.1", port.parse::<u16>().unwrap_or(3000))) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("buzz-provision: cannot reach relay on 127.0.0.1:{port}: {e}");
            std::process::exit(1);
        }
    };
    stream.write_all(req.as_bytes()).unwrap();
    stream.write_all(&body_bytes).unwrap();

    let mut resp = String::new();
    stream.read_to_string(&mut resp).ok();
    let status_line = resp.lines().next().unwrap_or("");
    let ok = status_line.contains(" 200") || status_line.contains(" 201");
    // The relay reports created vs existed in the body; surface it either way.
    let body_out = resp.split("\r\n\r\n").nth(1).unwrap_or("").trim();
    println!("buzz-provision {host}: {status_line} {body_out}");
    if !ok {
        std::process::exit(1);
    }
}
