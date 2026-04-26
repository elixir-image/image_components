defmodule Image.Component.Integration.ImgixTest do
  @moduledoc """
  End-to-end imgix-flavoured render-then-fetch: render an
  `Image.Component` with `cdn: :imgix`, point it at a Bandit
  running `Image.Plug.Provider.Imgix`, fetch every URL, validate.
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)

  use Image.Component.IntegrationCase,
    provider: {Image.Plug.Provider.Imgix, []},
    source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
    on_error: :status_text

  test "constrained <.image cdn={:imgix}> srcset round-trips through the imgix plug", ctx do
    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "p",
        width: 400,
        height: 400,
        sizes: "100vw",
        host: ctx.image_plug_host,
        scheme: "http",
        cdn: :imgix,
        url_options: [format: :jpeg]
      })

    entries = parse_srcset(html)
    assert length(entries) > 0

    for {url, {:width, expected_w}} <- entries do
      {:ok, response} = Req.get(url, decode_body: false)
      assert response.status == 200, "expected 200 for #{url}, got #{response.status}"

      {:ok, decoded} = Image.from_binary(response.body)
      assert Image.width(decoded) == expected_w
    end
  end

  test "signed imgix URLs from the component verify on the plug" do
    keys = ["component-imgix-key"]

    {:ok, server_pid} =
      Bandit.start_link(
        plug:
          {Image.Plug,
           [
             provider: {Image.Plug.Provider.Imgix, signing: %{keys: keys, required?: true}},
             source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
             on_error: :status_text
           ]},
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)
    on_exit(fn -> if Process.alive?(server_pid), do: Process.exit(server_pid, :shutdown) end)

    host = "127.0.0.1:#{port}"

    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "p",
        width: 200,
        height: 200,
        sizes: "100vw",
        host: host,
        scheme: "http",
        cdn: :imgix,
        url_options: [format: :jpeg],
        signing_keys: keys
      })

    [{url, _}] = parse_srcset(html) |> Enum.take(1)
    assert url =~ "?"
    assert url =~ "&s=" or url =~ "?s="

    {:ok, response} = Req.get(url, decode_body: false)
    assert response.status == 200
  end
end
