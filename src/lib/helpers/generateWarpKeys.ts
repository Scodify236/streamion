// Generates Cloudflare WARP credentials and outputs WireGuard environment variable format
const privateKey = crypto.getRandomValues(new Uint8Array(32));
privateKey[0] &= 248;
privateKey[31] &= 127;
privateKey[31] |= 64;

const b64Key = btoa(String.fromCharCode(...privateKey));

const regRes = await fetch("https://api.cloudflareclient.com/v0i2003111800/reg", {
    method: "POST",
    headers: {
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    },
    body: JSON.stringify({
        key: b64Key,
        tos: new Date().toISOString(),
        type: "ios",
        model: "iPhone11,6"
    })
});

const regData = await regRes.json();

if (!regData.success) {
    console.error("WARP Registration failed:", regData);
    Deno.exit(1);
}

const id = regData.result.id;
const token = regData.result.token;

const patchRes = await fetch(`https://api.cloudflareclient.com/v0i2003111800/reg/${id}`, {
    method: "PATCH",
    headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    },
    body: JSON.stringify({ warp_enabled: true })
});

const patchData = await patchRes.json();

console.log(`export WIREGUARD_INTERFACE_PRIVATE_KEY="${b64Key}"`);
console.log(`export WIREGUARD_INTERFACE_ADDRESS="${patchData.result.config.interface.addresses.v4}/32"`);
console.log(`export WIREGUARD_PEER_PUBLIC_KEY="${patchData.result.config.peers[0].public_key}"`);
console.log(`export WIREGUARD_PEER_ENDPOINT="162.159.192.5:2408"`);
