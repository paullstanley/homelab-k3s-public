#!/usr/bin/env python3
"""
build-wiki.py - turn docs/ into pages for this repository's GitHub Wiki tab.

docs/ in the main repository stays the single place you edit. This script produces a flat copy
that the Wiki tab can show: one page per guide, a Home page made from README.md, and a sidebar.

Run on your computer, from the root of this repository:

    git clone https://github.com/<ACCOUNT>/<REPO>.wiki.git ../wiki     # once; see note below
    python3 files/scripts/build-wiki.py ../wiki
    cd ../wiki && git add -A && git commit -m "Rebuild from docs" && git push

Note: GitHub only creates the wiki's own Git repository after the first page exists. Open the
Wiki tab, press "Create the first page", save it with any text, then clone.

What it changes on the way:
  - links between guides           -> wiki page names
  - links to files/, extras/, etc. -> full links into the main repository
  - every page gets a footer saying where its source is

It deletes every .md file in the target folder first, so pages removed from docs/ disappear from
the wiki too. Never edit pages in the Wiki tab: the next run overwrites them.

The repository address is read from "git remote get-url origin"; pass it as a second argument to
override:  python3 files/scripts/build-wiki.py ../wiki https://github.com/<ACCOUNT>/<REPO>
"""
import os, re, subprocess, sys

# docs path (without .md) -> wiki page name. The order here is the order in the sidebar.
PAGES = [
    ("Start here", [
        ("start-here/overview",                    "Overview"),
        ("start-here/build-from-nothing",          "Build-from-nothing"),
        ("start-here/conventions",                 "Conventions"),
    ]),
    ("Hardware", [
        ("hardware/asus-zenwifi-xt8",              "ASUS-ZenWiFi-XT8-router"),
        ("hardware/asus-aimesh-node",              "ASUS-AiMesh-node"),
        ("hardware/tp-link-archer-a7-openwrt",     "Archer-A7-on-OpenWrt"),
        ("hardware/tp-link-archer-ax21",           "Archer-AX21-access-point"),
        ("hardware/raspberry-pi",                  "Raspberry-Pi-for-k3s"),
        ("hardware/mac-lima-vm",                   "Mac-in-a-Lima-VM"),
    ]),
    ("Network", [
        ("network/address-plan",                   "Address-plan"),
        ("network/dns-design",                     "DNS-design"),
        ("network/isolated-iot-network",           "Isolated-IoT-network"),
        ("network/local-only-ipv6",                "Local-only-IPv6"),
        ("network/router-logging",                 "Router-logging"),
    ]),
    ("Kubernetes", [
        ("kubernetes/k3s-ha-cluster",              "HA-k3s-cluster"),
        ("kubernetes/load-balancers",              "Load-balancers"),
        ("kubernetes/coredns",                     "CoreDNS"),
        ("kubernetes/node-firewall",               "Node-firewall"),
    ]),
    ("Apps", [
        ("apps/pihole",                            "Pi-hole-on-k3s"),
        ("apps/homebridge",                        "Homebridge-on-k3s"),
        ("apps/homebridge-kasa-across-networks",   "Kasa-across-networks"),
        ("apps/homebridge-cameras",                "Homebridge-cameras"),
        ("apps/seerr-cloudflare-tunnel",           "Seerr-and-Cloudflare-tunnel"),
        ("apps/client-devices",                    "Client-devices"),
    ]),
    ("Operations", [
        ("operations/verification",                "Verification"),
        ("operations/backups-and-secrets",         "Backups-and-secrets"),
        ("operations/maintenance",                 "Maintenance"),
        ("operations/troubleshooting",             "Troubleshooting"),
        ("operations/software-and-firmware",       "Software-and-firmware"),
        ("operations/security-review",             "Security-review"),
        ("references",                             "References"),
    ]),
]
NAME = {src: name for _, items in PAGES for src, name in items}
LINK = re.compile(r"(\]\()([^)\s]+)(\))")
FENCE = re.compile(r"(```.*?```)", re.S)


def repo_url(argv):
    if len(argv) > 2:
        url = argv[2]
    else:
        url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()
    url = re.sub(r"^git@github\.com:", "https://github.com/", url)
    url = re.sub(r"\.git$", "", url).rstrip("/")
    if not url.startswith("https://"):
        sys.exit("Could not work out the repository address. Pass it as the second argument.")
    return url


def convert(text, src_dir, repo, problems, where):
    """Rewrite relative links. src_dir is the folder of the source file, relative to the repo root."""
    def fix(m):
        url = m.group(2)
        if re.match(r"(https?:|mailto:|#)", url):
            return m.group(0)
        path, _, frag = url.partition("#")
        target = os.path.normpath(os.path.join(src_dir, path)).replace(os.sep, "/")
        frag = "#" + frag if frag else ""
        if target.startswith("docs/") and target.endswith(".md"):
            key = target[len("docs/"):-len(".md")]
            if key in NAME:
                return m.group(1) + NAME[key] + frag + m.group(3)
            problems.append(f"{where}: link to a guide that is not in PAGES: {url}")
            return m.group(0)
        if not os.path.exists(target):
            problems.append(f"{where}: link target does not exist: {url}")
        kind = "tree" if os.path.isdir(target) else "blob"
        return m.group(1) + f"{repo}/{kind}/main/{target}{frag}" + m.group(3)
    parts = FENCE.split(text)
    return "".join(p if p.startswith("```") else LINK.sub(fix, p) for p in parts)


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.exit(__doc__)
    if not (os.path.isdir("docs") and os.path.isfile("README.md")):
        sys.exit("Run this from the root of the repository.")
    out = os.path.abspath(sys.argv[1])
    if not os.path.isdir(out):
        sys.exit(f"{out} does not exist. Clone the wiki repository there first (see the top of this script).")
    if os.path.commonpath([os.getcwd(), out]) == os.getcwd():
        sys.exit("The target must be outside this repository.")
    repo = repo_url(sys.argv)
    problems = []

    on_disk = {os.path.relpath(os.path.join(r, f), "docs")[:-3].replace(os.sep, "/")
               for r, _, fs in os.walk("docs") for f in fs if f.endswith(".md")}
    for missing in sorted(on_disk - set(NAME)):
        problems.append(f"docs/{missing}.md is not listed in PAGES, so it is not in the wiki")
    for gone in sorted(set(NAME) - on_disk):
        problems.append(f"PAGES lists docs/{gone}.md, which does not exist")

    for f in os.listdir(out):
        if f.endswith(".md"):
            os.remove(os.path.join(out, f))

    count = 0
    for _, items in PAGES:
        for src, name in items:
            path = f"docs/{src}.md"
            if not os.path.exists(path):
                continue
            text = open(path, encoding="utf-8").read()
            body = convert(text, os.path.dirname(path), repo, problems, path)
            body = body.rstrip("\n") + f"\n\n---\n\n*This page is generated from [`{path}`]({repo}/blob/main/{path}). Edit it there, not here.*\n"
            open(os.path.join(out, name + ".md"), "w", encoding="utf-8").write(body)
            count += 1

    home = convert(open("README.md", encoding="utf-8").read(), "", repo, problems, "README.md")
    home = home.rstrip("\n") + f"\n\n---\n\n*This page is generated from [`README.md`]({repo}/blob/main/README.md). Edit it there, not here.*\n"
    open(os.path.join(out, "Home.md"), "w", encoding="utf-8").write(home)

    side = ["**[Home](Home)**", ""]
    for section, items in PAGES:
        side.append(f"**{section}**")
        side.append("")
        for src, name in items:
            if os.path.exists(f"docs/{src}.md"):
                side.append(f"- [{name.replace('-', ' ')}]({name})")
        side.append("")
    side.append(f"[Files and scripts]({repo}/tree/main/files)")
    open(os.path.join(out, "_Sidebar.md"), "w", encoding="utf-8").write("\n".join(side) + "\n")
    open(os.path.join(out, "_Footer.md"), "w", encoding="utf-8").write(
        f"Generated from the [main repository]({repo}). Report problems as [issues]({repo}/issues).\n")

    print(f"{count} guide pages, Home, sidebar and footer written to {out}")
    if problems:
        print("\nCheck these:")
        for p in problems:
            print("  " + p)
        sys.exit(1)
    print("No broken links.")


if __name__ == "__main__":
    main()
