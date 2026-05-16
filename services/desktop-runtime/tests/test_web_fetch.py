"""Tests for web_fetch in desktop_runtime.tools.web_tools."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from desktop_runtime.tools.web_tools import _parse_cookies, web_fetch


# ---------------------------------------------------------------------------
# Unit: cookie parser
# ---------------------------------------------------------------------------

def test_cookie_parsing():
    result = _parse_cookies("a=1; b=2")
    assert result == {"a": "1", "b": "2"}


def test_cookie_parsing_strips_whitespace():
    result = _parse_cookies("  x = hello ; y=world  ")
    assert result == {"x": "hello", "y": "world"}


def test_cookie_parsing_empty_string():
    assert _parse_cookies("") == {}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mock_response(text: str = "<p>Hello</p>", status_code: int = 200):
    resp = MagicMock(spec=httpx.Response)
    resp.status_code = status_code
    resp.text = text
    resp.raise_for_status = MagicMock()
    return resp


def _mock_status_error(status_code: int, url: str = "https://example.com"):
    request = MagicMock()
    response = MagicMock(spec=httpx.Response)
    response.status_code = status_code
    return httpx.HTTPStatusError("error", request=request, response=response)


# ---------------------------------------------------------------------------
# Async tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_basic_fetch():
    resp = _mock_response("<p>Hello world</p>")
    mock_client = AsyncMock()
    mock_client.get = AsyncMock(return_value=resp)

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com")

    mock_client.get.assert_called_once()
    call_kwargs = mock_client.get.call_args
    assert call_kwargs[0][0] == "https://example.com"
    assert "Hello world" in result


@pytest.mark.asyncio
async def test_with_cookies():
    resp = _mock_response("<p>Private content</p>")
    mock_client = AsyncMock()
    mock_client.get = AsyncMock(return_value=resp)

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com", cookies="session=abc; token=xyz")

    _, kwargs = mock_client.get.call_args
    assert kwargs["cookies"] == {"session": "abc", "token": "xyz"}
    assert "Private content" in result


@pytest.mark.asyncio
async def test_401_message():
    mock_client = AsyncMock()
    err = _mock_status_error(401)
    resp = _mock_response()
    resp.raise_for_status = MagicMock(side_effect=err)
    mock_client.get = AsyncMock(return_value=resp)

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com")

    assert "401" in result or "403" in result
    assert "cookies" in result


@pytest.mark.asyncio
async def test_403_message():
    mock_client = AsyncMock()
    err = _mock_status_error(403)
    resp = _mock_response()
    resp.raise_for_status = MagicMock(side_effect=err)
    mock_client.get = AsyncMock(return_value=resp)

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com")

    assert "cookies" in result


@pytest.mark.asyncio
async def test_404_returns_http_code():
    mock_client = AsyncMock()
    err = _mock_status_error(404, "https://example.com/missing")
    resp = _mock_response()
    resp.raise_for_status = MagicMock(side_effect=err)
    mock_client.get = AsyncMock(return_value=resp)

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com/missing")

    assert result.startswith("HTTP 404")


@pytest.mark.asyncio
async def test_timeout():
    mock_client = AsyncMock()
    mock_client.get = AsyncMock(side_effect=httpx.TimeoutException("timed out"))

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com")

    assert "timed out" in result.lower()


@pytest.mark.asyncio
async def test_invalid_url():
    result = await web_fetch("ftp://example.com/file.txt")
    assert "Error" in result
    assert "http" in result.lower()


@pytest.mark.asyncio
async def test_length_limit():
    long_html = "<p>" + "x" * 5000 + "</p>"
    resp = _mock_response(long_html)
    mock_client = AsyncMock()
    mock_client.get = AsyncMock(return_value=resp)

    with patch("desktop_runtime.tools.web_tools.httpx.AsyncClient") as MockClient:
        MockClient.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        MockClient.return_value.__aexit__ = AsyncMock(return_value=False)

        result = await web_fetch("https://example.com")

    assert len(result) <= 3000 + len("...(truncated)")
    assert result.endswith("...(truncated)")
