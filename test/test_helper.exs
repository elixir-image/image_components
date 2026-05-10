# Exclude the slow / external-dependency suites by default. Run
# them explicitly with `mix test --include cross_sdk` (requires
# Node + npm install in test/support/cross_sdk/) or
# `mix test --include live_cdn` (requires network access). See
# README's Testing section for details.
ExUnit.start(exclude: [:cross_sdk, :live_cdn, :live_iiif])
