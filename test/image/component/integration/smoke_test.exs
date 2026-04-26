defmodule Image.Component.Integration.SmokeTest do
  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Cloudflare, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  test "harness boots and a rendered URL fetches a real image", ctx do
    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "p",
        width: 200,
        height: 200,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        url_options: [format: :jpeg]
      })

    [src] = image_srcs(html)
    assert String.starts_with?(src, "http://#{ctx.image_plug_host}/cdn-cgi/image/")

    {:ok, response} = Req.get(src, decode_body: false)
    assert response.status == 200

    {:ok, decoded} = Image.from_binary(response.body)
    assert is_struct(decoded, Vix.Vips.Image)
  end
end
