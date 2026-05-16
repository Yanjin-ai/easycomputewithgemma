import re
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup


def _parse_cookies(cookies: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for pair in cookies.split(";"):
        pair = pair.strip()
        if "=" in pair:
            k, v = pair.split("=", 1)
            parsed[k.strip()] = v.strip()
    return parsed


def _clean_html(html: str) -> str:
    # Remove nav/header/footer/aside blocks before stripping tags
    for tag in ("nav", "header", "footer", "aside"):
        html = re.sub(
            rf"<{tag}[\s>].*?</{tag}>", " ", html, flags=re.IGNORECASE | re.DOTALL
        )
    # Remove script/style blocks
    html = re.sub(
        r"<(script|style)[\s>].*?</(script|style)>",
        " ",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )
    # Strip remaining tags
    text = re.sub(r"<[^>]+>", " ", html)
    # Collapse whitespace, preserve single blank lines
    text = re.sub(r" +", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


async def web_fetch(url: str, cookies: str = "") -> str:
    """
    Fetch a webpage and return its text content.

    Args:
        url: The URL to fetch (must start with http:// or https://)
        cookies: Optional cookie string in Netscape/header format.
                 Paste from browser DevTools → Network → Request Headers → Cookie.
                 Example: "session_id=abc123; auth_token=xyz789"

    Returns the page text content (HTML stripped, max 3000 chars).
    For pages requiring login, provide the cookies parameter.
    """
    parsed_url = urlparse(url)
    if parsed_url.scheme not in {"http", "https"}:
        return "Error: only http:// and https:// URLs are supported"

    cookie_dict = _parse_cookies(cookies) if cookies.strip() else {}

    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=15.0) as client:
            response = await client.get(
                url,
                headers={"User-Agent": "Mozilla/5.0"},
                cookies=cookie_dict,
            )
            response.raise_for_status()
    except httpx.HTTPStatusError as e:
        code = e.response.status_code
        if code in (401, 403):
            return (
                "Access denied (401/403). If login is required, provide cookies parameter."
            )
        return f"HTTP {code}: {url}"
    except httpx.TimeoutException:
        return "Request timed out after 15 seconds"
    except Exception as e:
        return f"Error: web_fetch failed: {e}"

    text = _clean_html(response.text)
    if len(text) > 3000:
        return text[:3000] + "...(truncated)"
    return text


async def web_search(query: str) -> str:
    """Search the web using DuckDuckGo and return top 5 results as text."""
    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=15.0) as client:
            response = await client.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query},
                headers={"User-Agent": "Mozilla/5.0"},
            )
        soup = BeautifulSoup(response.text, "html.parser")
        results = []
        for item in soup.select(".result__body")[:5]:
            title = item.select_one(".result__title")
            snippet = item.select_one(".result__snippet")
            if title and snippet:
                results.append(f"• {title.get_text(strip=True)}: {snippet.get_text(strip=True)}")
        return "\n".join(results) if results else "No results found"
    except Exception as e:
        return f"[error] web_search failed: {e}"
