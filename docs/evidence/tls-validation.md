# TLS / DNS / OAuth / Streaming — End-to-End Validation

Required by FINAL-PROJECT.md Appendix A.4. Every item below must be proven
**from the public hostname**, not from the EC2 itself. Each item needs a
timestamped screenshot or a `tee`-captured command output. Identity binding:
your ESADE email AND the public HTTPS URL must be visible in the same frame.

- **Chosen solution**: Free dynamic-DNS (DuckDNS) + self-hosted Caddy on the EC2,
  Let's Encrypt / ZeroSSL (Caddy's defaults), on one Elastic IP (`52.31.85.106`):
  - `https://alicenl-lobechat.duckdns.org` → LobeChat
  - `https://alicenl-lobechat.duckdns.org:8443` → Casdoor SSO (OIDC issuer)
  - `https://alicenl-minio.duckdns.org` → MinIO S3 API
- **Why DuckDNS** (per Appendix A.3): each `*.duckdns.org` label is its own
  registered domain on the public-suffix list, so this deployment gets its own
  CA rate-limit budget.
- **Why Casdoor on `:8443` (same hostname) rather than its own subdomain**:
  DuckDNS nameservers intermittently timed out on the CA's **CAA** lookup, making
  a 3rd cert unreliable. Serving Casdoor on `:8443` reuses the working lobechat
  cert and removes that dependency. OIDC issuer = `https://alicenl-lobechat.duckdns.org:8443`.

---

## Checklist

### 1. Casdoor login completes from the public URL
<!-- Screenshot: full OAuth round-trip ending logged-in in LobeChat, no
     Secure-cookie / redirect_uri errors. Address bar + padlock visible. -->
- [x] PASS — Casdoor login completed; see `lobechat-https.png` (logged-in profile with ESADE email).

### 2. Chat streaming works (SSE)
<!-- Screenshot mid-stream: tokens arriving incrementally. -->
- [x] PASS — see `chat-mcp.png` (reply streamed on local `qwen2.5:3b`).

### 3. An MCP tool returns a result in chat
<!-- A secret-free MCP server (e.g. filesystem / d2 / aws-documentation) invoked
     from chat, result rendered. -->
- [x] PASS — see `chat-mcp.png` (`aws-documentation` MCP tool called via MCPHub, results returned + cited).

### 4. File upload to MinIO from chat works
<!-- Upload a file in chat; it renders/downloads back. Confirms presigned-URL
     host + CORS + request-size path through Caddy. -->
- [x] PASS — `tls-04-upload.png` (PDF uploaded to the MinIO `lobe` bucket over HTTPS).

### 5. Direct origin access is rejected
<!-- From your laptop, bypassing the proxy hostname. Port 47000 is closed in the
     security group (timeout); IP-on-443 has no matching Caddy site (TLS/host
     rejected). Paste both outputs. -->
```
$ curl -v --max-time 6 http://52.31.85.106:47000/
*   Trying 52.31.85.106:47000...
* Connection timed out after 6002 milliseconds      # SG blocks 47000

$ curl -sI --max-time 6 https://52.31.85.106/        # bare IP, no SNI match
curl: (35) TLS connect error: tlsv1 alert internal error   # Caddy has no site for a bare IP -> rejected
```
- [x] PASS — port 47000 times out (security group); bare-IP HTTPS rejected by Caddy (no matching site).

### 6. Valid public certificate chain
<!-- Issuer = Let's Encrypt (R3/E-series), hostname matches, not expired. -->
```
$ echo | openssl s_client -connect alicenl-lobechat.duckdns.org:443 \
    -servername alicenl-lobechat.duckdns.org 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates
issuer=C=AT, O=ZeroSSL GmbH, CN=ZeroSSL ECC DV SSL CA 2
subject=CN=alicenl-lobechat.duckdns.org
notBefore=Jun  1 00:00:00 2026 GMT
notAfter=Aug 30 23:59:59 2026 GMT
```
Public CA (ZeroSSL), hostname matches, valid window. Casdoor `:8443` reuses this cert.
- [x] PASS — `tls-06-cert.png` (Firefox: issuer ZeroSSL GmbH, TLS 1.3).

---

_All items must pass. Failing any one caps the practical score at 50%._
