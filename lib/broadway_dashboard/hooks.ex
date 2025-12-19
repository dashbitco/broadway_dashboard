defmodule BroadwayDashboard.Hooks do
  @moduledoc """
  LiveView hooks for Broadway Dashboard pan/zoom functionality.

  This module provides an `on_mount` callback that registers the JavaScript
  hooks required for pan/zoom functionality on the pipeline graph.

  ## Usage

  Add this module to your LiveDashboard configuration in your router:

      live_dashboard "/dashboard",
        additional_pages: [
          broadway: BroadwayDashboard
        ],
        on_mount: [BroadwayDashboard.Hooks]

  The hooks will automatically be injected into the page head, enabling
  pan/zoom functionality on the pipeline visualization.

  ## Features

  - **Mouse wheel zoom**: Scroll to zoom in/out, centered on cursor position
  - **Drag to pan**: Click and drag to move the view
  - **Touch support**: Pinch to zoom and drag to pan on touch devices
  - **Zoom controls**: Buttons for zoom in, zoom out, reset, and fit-to-view

  ## Manual JavaScript Setup (Alternative)

  If you prefer to bundle the JavaScript yourself instead of using `on_mount`:

  1. Copy `priv/static/js/broadway_dashboard.js` to your assets
  2. Import and register the hooks with your LiveSocket:

      ```javascript
      import BroadwayDashboardHooks from "./broadway_dashboard.js"

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: { ...BroadwayDashboardHooks }
      })
      ```

  Note: When using the manual setup, you don't need to add this module
  to the `on_mount` configuration.
  """

  import Phoenix.Component

  alias Phoenix.LiveDashboard.PageBuilder

  @doc """
  Callback for `on_mount` that registers the Broadway Dashboard JavaScript hooks.
  """
  def on_mount(:default, _params, _session, socket) do
    {:cont, PageBuilder.register_after_opening_head_tag(socket, &after_opening_head_tag/1)}
  end

  defp after_opening_head_tag(assigns) do
    ~H"""
    <script nonce={@csp_nonces[:script]}>
      <%= Phoenix.HTML.raw(BroadwayDashboard.PanZoom.javascript_code()) %>
    </script>
    <style nonce={@csp_nonces[:style]}>
      <%= Phoenix.HTML.raw(BroadwayDashboard.PanZoom.css_code()) %>
    </style>
    """
  end
end
