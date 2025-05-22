defmodule Hermes.Server.Phoenix.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest

  # Define a test router that uses the MCP router macros
  defmodule TestRouter do
    use Phoenix.Router
    import Hermes.Server.Phoenix.Router

    pipeline :api do
      plug :accepts, ["json"]
    end

    scope "/api" do
      pipe_through :api
      
      mcp_endpoints "/mcp", Hermes.Server.Phoenix.RouterTest.TestController
    end
  end

  # Define a test controller
  defmodule TestController do
    use Phoenix.Controller
    
    def handle(conn, _params) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{result: "success"}))
    end
    
    def handle_stream(conn, _params) do
      conn
      |> put_resp_content_type("application/x-ndjson")
      |> send_resp(200, "")
    end
  end
  
  # Define a test MCP server module
  defmodule TestMCPServer do
    def child_spec(_opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :worker
      }
    end

    def start_link do
      {:ok, self()}
    end
  end

  # Set the endpoint for Phoenix.ConnTest
  @endpoint TestRouter
  
  setup do
    :ok
  end

  describe "mcp_server/2" do
    test "adds the MCP route to the router" do
      # Get the routes from the router
      routes = TestRouter.__routes__()
      
      # Find the MCP route
      mcp_route = Enum.find(routes, fn route -> 
        route.path == "/api/mcp" && route.verb == :post
      end)
      
      # Assert the route exists and has the correct properties
      assert mcp_route != nil
      assert mcp_route.helper == "mcp"
      assert mcp_route.plug == Hermes.Server.Phoenix.RouterTest.TestController
      # The server is not automatically set in the plug_opts, it would be set in the controller
    end
  end
end
