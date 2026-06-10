# hersoul.ai static site

> Last updated: 2026-05-02

## Host

- Server: `root@75.127.3.187`
- Purpose: overseas static marketing site for `hersoul.ai`
- Web root: `/var/www/hersoul-ai`
- Nginx site: `/etc/nginx/sites-available/hersoul-ai`
- DNS provider: NameSilo / DNS Owl

## Ports

| Port | Owner | Notes |
|------|-------|-------|
| `80` | nginx | redirects to HTTPS except ACME challenge path |
| `443` | nginx | `hersoul.ai` / `www.hersoul.ai` |
| `8443` | File Browser | moved from `443`, still uses `/root/.certs/cert.pem` for `suyuan.duckdns.org` |

File Browser service:

```bash
systemctl cat filebrowser
systemctl status filebrowser --no-pager -l
```

## Certificate

Let's Encrypt certificate:

```text
/etc/letsencrypt/live/hersoul.ai/fullchain.pem
/etc/letsencrypt/live/hersoul.ai/privkey.pem
```

Domains:

```text
hersoul.ai
www.hersoul.ai
```

The existing File Browser certificate is for `suyuan.duckdns.org`, not `hersoul.ai`.

## Verify

```bash
curl -I https://hersoul.ai/
curl -I https://www.hersoul.ai/
echo | openssl s_client -connect 75.127.3.187:443 -servername hersoul.ai 2>/dev/null | openssl x509 -noout -issuer -subject -dates -ext subjectAltName
ssh root@75.127.3.187 "systemctl is-active nginx filebrowser; ss -ltnp | grep -E ':(80|443|8443)\\b'"
```

## Rollback

Restore File Browser to `443` only if nginx HTTPS is intentionally disabled:

```bash
ssh root@75.127.3.187
cp -a /etc/systemd/system/filebrowser.service.bak-* /tmp/
perl -0pi -e 's/-a 0\\.0\\.0\\.0 -p 8443/-a 0.0.0.0 -p 443/' /etc/systemd/system/filebrowser.service
systemctl daemon-reload
systemctl restart filebrowser
systemctl stop nginx
```

Nginx config backups are kept as `/etc/nginx/sites-available/hersoul-ai.bak-*`.
