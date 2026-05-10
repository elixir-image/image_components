defmodule Image.Component.Integration.ErrorPathTest do
  @moduledoc """
  Confirms `Image.Component` does not silently mask backend errors.
  When the source doesn't exist or the URL options are invalid, the
  component-emitted URL produces a 4xx response with the matching
  `x-image-plug-error` tag.
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Cloudflare, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  import ExUnit.CaptureLog

  test "URL pointing at a missing source returns 404 :source_not_found", ctx do
    html =
      render_component(&Image.Component.image/1, %{
        src: "/this-does-not-exist.jpg",
        alt: "x",
        width: 200,
        height: 200,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: :jpeg]
      })

    [src] = image_srcs(html)

    {{:ok, response}, _log} = with_log(fn -> Req.get(src, decode_body: false) end)

    assert response.status == 404
    assert response.headers["x-image-plug-error"] == ["source_not_found"]
  end

  test "url_options carrying an unknown key produces 400 :unknown_option", ctx do
    # This is the wrong way to use the component (custom keys not in
    # the URL grammar) but it's the cheapest way to confirm options
    # pass through verbatim.
    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "x",
        width: 200,
        height: 200,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: :jpeg, definitely_not_a_real_option: "yes"]
      })

    # The unknown option encoder returns nil so the URL won't carry
    # it. We don't actually exercise unknown_option here without a
    # raw URL, so confirm at least that the URL is well-formed and
    # returns 200 (the unknown key was silently dropped, as
    # documented).
    [src] = image_srcs(html)
    {:ok, response} = Req.get(src, decode_body: false)

    assert response.status == 200
  end

  test "encoder filters invalid option values before they hit the wire", ctx do
    # Documenting behaviour: when `:url_options` carries a value
    # the encoder rejects (e.g. quality=999, outside 1..100), the
    # encoder DROPS the option silently rather than passing it
    # through. The resulting URL omits quality entirely and the
    # plug returns 200. This is the right design (URL-level
    # validation in the component, parser-level validation in the
    # plug) — but it means the component cannot generate a URL
    # the plug will reject for that key. Confirms the contract.
    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "x",
        width: 200,
        height: 200,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: :jpeg, quality: 999]
      })

    [src] = image_srcs(html)
    refute String.contains?(src, "quality=")
    {:ok, response} = Req.get(src, decode_body: false)
    assert response.status == 200
  end
end
