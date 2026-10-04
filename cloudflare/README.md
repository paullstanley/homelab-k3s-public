# Cloudflare

Settings that live in the Cloudflare dashboard, recorded here because nothing else holds them. Steps: [docs/09](../docs/09-seerr-and-cloudflare.md).

| Item | Value |
| --- | --- |
| Zone | `example.com` |
| Tunnel connector | `cloudflared`, installed as a system service on the k3sprimary host (not in the cluster) |
| Tunnel management | Dashboard-managed (Zero Trust → Networks → Tunnels) |
| Tunnel name | `<FILL IN>` |
| Tunnel token | In the password manager. Never here |

## Published application routes

| Public name | Service type | URL | Serves |
| --- | --- | --- | --- |
| `request.example.com` | HTTP | `192.168.50.12` | Seerr, through Traefik |

The URL must be Traefik's address. `localhost:80` stopped working on 3 October when Traefik moved off the nodes' own addresses.

## DNS records

| Name | Type | Target | Proxy |
| --- | --- | --- | --- |
| `request` | CNAME | the tunnel (created automatically with the route) | Proxied |

`home.example.com` names are **not** in Cloudflare. They exist only in Pi-hole.

Other records in the zone were not reviewed. Export them once for the record: dashboard → DNS → Records → Import and Export → Export, and keep the file with your backups (it contains no secrets, but lists everything you publish).
