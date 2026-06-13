"""Fetch public web pages via Jina -> Firecrawl -> direct fallback.

Secrets are loaded from .env files but never printed. This script is meant for
Claude Code agents to get token-friendly page content without reading .env.
"""

from __future__ import annotations

import argparse
import html
import ipaddress
import os
import re
import socket
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse, urljoin

import httpx
from dotenv import load_dotenv

TIMEOUT = 20.0
MAX_CHARS = 20_000
DEFAULT_CHARS = 8_000
FIRECRAWL_URL = "https://api.firecrawl.dev/v1/scrape"


def load_env() -> None:
    """Load repo/global env files without printing values.

    Precedence is lower to higher:
      $CLAUDE_HOME/.env < repo-root .env < process environment
    """
    home_env = Path.home() / ".claude" / ".env"
    repo_env = Path(__file__).resolve().parents[2] / ".env"
    load_dotenv(home_env, override=False)
    load_dotenv(repo_env, override=False)


class ProviderError(RuntimeError):
    def __init__(self, provider: str, message: str):
        super().__init__(f"{provider}: {message}")
        self.provider = provider
        self.message = message


class SafetyError(RuntimeError):
    pass


def is_blocked_ip(address: str) -> bool:
    ip = ipaddress.ip_address(address)
    return bool(
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
    )


def validate_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise SafetyError("only http/https URLs are allowed")
    if parsed.username or parsed.password:
        raise SafetyError("URLs with embedded credentials are blocked")
    if not parsed.hostname:
        raise SafetyError("URL has no hostname")
    if parsed.hostname in {"localhost", "localhost.localdomain"} or parsed.hostname.endswith(".local") or parsed.hostname.endswith(".internal"):
        raise SafetyError("local/internal hostnames are blocked")
    try:
        for info in socket.getaddrinfo(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80), type=socket.SOCK_STREAM):
            if is_blocked_ip(info[4][0]):
                raise SafetyError(f"blocked address for hostname: {parsed.hostname}")
    except socket.gaierror as exc:
        raise SafetyError(f"DNS lookup failed: {exc}") from exc
    return parsed.geturl()


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.skip = 0
        self.parts: list[str] = []
        self.title = ""
        self._in_title = False

    def handle_starttag(self, tag: str, attrs) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "svg"}:
            self.skip += 1
        if tag == "title":
            self._in_title = True
        if tag in {"p", "div", "section", "article", "br", "li", "h1", "h2", "h3", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "svg"} and self.skip:
            self.skip -= 1
        if tag == "title":
            self._in_title = False
        if tag in {"p", "div", "section", "article", "li", "h1", "h2", "h3", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if self.skip:
            return
        text = html.unescape(data).strip()
        if not text:
            return
        if self._in_title:
            self.title += text
        self.parts.append(text + " ")

    def text(self) -> str:
        return re.sub(r"\n{3,}", "\n\n", re.sub(r"[ \t]+", " ", "".join(self.parts))).strip()


def direct_fetch(url: str, fmt: str) -> tuple[str | None, str]:
    current = validate_url(url)
    with httpx.Client(timeout=TIMEOUT, follow_redirects=False, headers={"user-agent": "harness-web-fetch/0.1"}) as client:
        for _ in range(5):
            resp = client.get(current)
            if resp.status_code in {301, 302, 303, 307, 308}:
                loc = resp.headers.get("location")
                if not loc:
                    raise ProviderError("direct", "redirect without Location")
                current = validate_url(urljoin(current, loc))
                continue
            resp.raise_for_status()
            if fmt == "html":
                return None, resp.text
            parser = TextExtractor()
            parser.feed(resp.text)
            return parser.title or None, parser.text()
    raise ProviderError("direct", "too many redirects")


def jina_fetch(url: str, fmt: str) -> tuple[str | None, str]:
    validate_url(url)
    headers = {"accept": "text/plain"}
    key = os.environ.get("JINA_API_KEY")
    if key:
        headers["authorization"] = f"Bearer {key}"
    resp = httpx.get(f"https://r.jina.ai/{url}", headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    text = resp.text.strip()
    if not text:
        raise ProviderError("jina", "empty response")
    title = None
    m = re.search(r"^Title:\s*(.+)$", text, re.MULTILINE)
    if m:
        title = m.group(1).strip()
    return title, text


def firecrawl_fetch(url: str, fmt: str, wait_for_ms: int = 0) -> tuple[str | None, str]:
    validate_url(url)
    key = os.environ.get("FIRECRAWL_API_KEY")
    if not key:
        raise ProviderError("firecrawl", "missing FIRECRAWL_API_KEY")
    out_format = "html" if fmt == "html" else "markdown"
    payload: dict = {"url": url, "formats": [out_format]}
    if wait_for_ms > 0:
        payload["waitFor"] = wait_for_ms
    resp = httpx.post(
        FIRECRAWL_URL,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json=payload,
        timeout=60,
    )
    resp.raise_for_status()
    data = resp.json()
    if not data.get("success"):
        raise ProviderError("firecrawl", f"API error: {data.get('error') or 'unknown'}")
    payload = data.get("data") or {}
    text = payload.get(out_format) or payload.get("markdown") or payload.get("html") or ""
    if not text:
        raise ProviderError("firecrawl", "empty response")
    meta = payload.get("metadata") or {}
    return meta.get("title"), text.strip()


def provider_order(requested: str) -> list[str]:
    all_providers = ["jina", "firecrawl", "direct"]
    return all_providers if requested == "auto" else [requested]


def truncate(text: str, max_chars: int, offset: int) -> tuple[str, int | None]:
    chunk = text[offset : offset + max_chars]
    nxt = offset + len(chunk) if offset + len(chunk) < len(text) else None
    return chunk, nxt


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch a public URL via Jina -> Firecrawl -> direct")
    parser.add_argument("url")
    parser.add_argument("--provider", choices=["auto", "jina", "firecrawl", "direct"], default="auto")
    parser.add_argument("--format", choices=["markdown", "text", "html"], default="markdown")
    parser.add_argument("--max-chars", type=int, default=DEFAULT_CHARS)
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument(
        "--wait-for",
        type=int,
        default=0,
        metavar="MS",
        help="ms to wait for JS to settle; passed to Firecrawl as waitFor. No-op on jina/direct.",
    )
    args = parser.parse_args()

    load_env()
    max_chars = min(max(args.max_chars, 1000), MAX_CHARS)
    if args.wait_for > 0 and args.provider in {"jina", "direct"}:
        print(
            f"warning: --wait-for has no effect on provider={args.provider}; firecrawl only",
            file=sys.stderr,
        )
    errors: list[str] = []

    for provider in provider_order(args.provider):
        try:
            if provider == "jina":
                title, text = jina_fetch(args.url, args.format)
            elif provider == "firecrawl":
                title, text = firecrawl_fetch(args.url, args.format, args.wait_for)
            else:
                title, text = direct_fetch(args.url, args.format)
            chunk, next_offset = truncate(text, max_chars, args.offset)
            print(f"provider: {provider}")
            print(f"url: {args.url}")
            print(f"chars: {args.offset}-{args.offset + len(chunk)} of {len(text)}")
            if next_offset is not None:
                print(f"nextOffset: {next_offset}")
            if title:
                print(f"title: {title}")
            if errors:
                print("fallbacks: " + "; ".join(errors))
            print("\n--- BEGIN UNTRUSTED WEB CONTENT ---")
            print(chunk)
            print("--- END UNTRUSTED WEB CONTENT ---")
            return 0
        except SafetyError:
            raise
        except Exception as exc:
            errors.append(f"{provider}: {exc}")

    print("All providers failed: " + "; ".join(errors), file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SafetyError as exc:
        print(f"Safety error: {exc}", file=sys.stderr)
        raise SystemExit(2)
