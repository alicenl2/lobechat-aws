# TLS / DNS / OAuth / Streaming — End-to-End Validation

Required by FINAL-PROJECT.md Appendix A.4. Every item below must be proven
**from the public hostname**, not from the EC2 itself. Each item needs a
timestamped screenshot or a `tee`-captured command output. Identity binding:
your ESADE email AND the public HTTPS URL must be visible in the same frame.

- **Chosen solution**: Free dynamic-DNS (DuckDNS) + self-hosted Caddy on the EC2,
  Let's Encrypt HTTP-01. Three subdomains on one Elastic IP:
  - `https://alicenl-lobechat.duckdns.org` → LobeChat
  - `https://alicenl-casdoor.duckdns.org` → Casdoor SSO
  - `https://alicenl-minio.duckdns.org` → MinIO S3 API
- **Why DuckDNS** (per Appendix A.3): each `*.duckdns.org` label is its own
  registered domain on the Let's Encrypt public-suffix list, so this deployment
  gets its own LE rate-limit budget — no contention with classmates on demo day.

---

## Checklist

### 1. Casdoor login completes from the public URL
<!-- Screenshot: full OAuth round-trip ending logged-in in LobeChat, no
     Secure-cookie / redirect_uri errors. Address bar + padlock visible. -->
- [ ] PASS — screenshot: `tls-01-login.png`

### 2. Chat streaming works (SSE)
<!-- Screenshot mid-stream: tokens arriving incrementally. -->
- [ ] PASS — screenshot: `tls-02-streaming.png`

### 3. An MCP tool returns a result in chat
<!-- A secret-free MCP server (e.g. filesystem / d2 / aws-documentation) invoked
     from chat, result rendered. -->
- [ ] PASS — screenshot: `tls-03-mcp.png`

### 4. File upload to MinIO from chat works
<!-- Upload a file in chat; it renders/downloads back. Confirms presigned-URL
     host + CORS + request-size path through Caddy. -->
- [ ] PASS — screenshot: `tls-04-upload.png`

### 5. Direct origin access is rejected
<!-- From your laptop, bypassing the proxy hostname. Port 47000 is closed in the
     security group (timeout); IP-on-443 has no matching Caddy site (TLS/host
     rejected). Paste both outputs. -->
```
$ curl -v --max-time 5 http://<EIP>:47000/
TODO (expect: connection timed out — security group blocks 47000)

$ curl -sI --max-time 5 https://<EIP>/ --resolve dummy:443:<EIP>
TODO (expect: TLS/host rejected — no Caddy site matches a bare IP)
```

### 6. Valid public certificate chain
<!-- Issuer = Let's Encrypt (R3/E-series), hostname matches, not expired. -->
```
$ echo | openssl s_client -connect alicenl-lobechat.duckdns.org:443 \
    -servername alicenl-lobechat.duckdns.org 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates
TODO
```
- [ ] PASS — screenshot of browser cert panel: `tls-06-cert.png`

---

_All items must pass. Failing any one caps the practical score at 50%._
