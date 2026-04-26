defmodule Image.Component.Integration.SigningTest do
  @moduledoc """
  End-to-end signed URLs: render an `Image.Component` with
  `:signing_keys`, fetch every emitted URL through a real
  `Image.Plug` configured with the same `:signing` keys + required.
  Tampered or unsigned URLs against the same plug return 401.
  """

  @fixtures Path.expand("../../../fixtures/images", __DIR__)
  @keys ["component-integration-secret"]

  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Image.Component.IntegrationCase, only: [parse_srcset: 1]

  setup_all do
    {:ok, server_pid} =
      Bandit.start_link(
        plug:
          {Image.Plug,
           [
             provider: {Image.Plug.Provider.Cloudflare, []},
             source_resolver: {Image.Plug.SourceResolver.File, root: @fixtures},
             on_error: :status_text,
             signing: %{keys: @keys, required?: true}
           ]},
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)

    on_exit(fn ->
      if Process.alive?(server_pid), do: Process.exit(server_pid, :shutdown)
    end)

    {:ok, %{base_url: "http://127.0.0.1:#{port}", host: "127.0.0.1:#{port}"}}
  end

  test "every srcset URL signed by the component is verified + served by the plug", ctx do
    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "p",
        width: 400,
        height: 400,
        sizes: "100vw",
        host: ctx.host,
        scheme: "http",
        url_options: [format: :jpeg],
        signing_keys: @keys
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

  test "unsigned component URLs return 401 against a signing-required plug", ctx do
    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "p",
        width: 400,
        height: 400,
        sizes: "100vw",
        host: ctx.host,
        scheme: "http",
        url_options: [format: :jpeg]
        # no :signing_keys
      })

    [{url, _}] = parse_srcset(html) |> Enum.take(1)
    {:ok, response} = Req.get(url, decode_body: false)

    assert response.status == 401
    assert response.headers["x-image-plug-error"] == ["signature_required"]
  end

  test "expiry round-trips via the component", ctx do
    expiry = System.system_time(:second) + 3600

    html =
      render_component(&Image.Component.image/1, %{
        src: "/portrait.jpg",
        alt: "p",
        width: 200,
        height: 200,
        sizes: "100vw",
        host: ctx.host,
        scheme: "http",
        url_options: [format: :jpeg],
        signing_keys: @keys,
        signing_expires_at: expiry
      })

    [{url, _}] = parse_srcset(html) |> Enum.take(1)
    assert url =~ "?exp=#{expiry}"
    assert url =~ "&sig="

    {:ok, response} = Req.get(url, decode_body: false)
    assert response.status == 200
  end
end
