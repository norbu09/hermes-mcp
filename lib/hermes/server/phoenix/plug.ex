defmodule Hermes.Server.Phoenix.Plug do
  @moduledoc """
  Plug for Hermes MCP server.
  
  This module provides plugs that can be used in Phoenix applications
  to handle authentication and request processing for MCP endpoints.
  
  ## Usage
  
  ```elixir
  defmodule MyAppWeb.Router do
    use Phoenix.Router
    import Hermes.Server.Phoenix.Router
    
    pipeline :api do
      plug :accepts, ["json"]
    end
    
    pipeline :mcp_api do
      plug :accepts, ["json"]
      plug Hermes.Server.Phoenix.Plug.Authentication, auth_fn: &MyApp.Auth.authenticate/1
    end
    
    scope "/api" do
      pipe_through :mcp_api
      
      mcp_endpoints "/mcp", MyAppWeb.MCPController
    end
  end
  ```
  """
  
  @doc """
  Captures the raw request body for later use.
  
  This plug captures the raw request body and stores it in the connection
  for later use by the controller.
  """
  def capture_raw_body(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.put_private(conn, :raw_body, body)
  end
  
  defmodule Authentication do
    @moduledoc """
    Authentication plug for Hermes MCP server.
    
    This plug provides authentication for MCP endpoints. It can be configured
    with a custom authentication function that will be called with the connection.
    """
    
    import Plug.Conn
    
    @doc """
    Initializes the authentication plug.
    
    ## Options
    
    - `:auth_fn` - A function that takes a connection and returns either
      `{:ok, conn}` or `{:error, reason}` (required)
    - `:error_handler` - A function that takes a connection and an error reason
      and returns a connection (optional)
    """
    def init(opts) do
      auth_fn = Keyword.fetch!(opts, :auth_fn)
      error_handler = Keyword.get(opts, :error_handler, &default_error_handler/2)
      
      %{
        auth_fn: auth_fn,
        error_handler: error_handler
      }
    end
    
    @doc """
    Calls the authentication function and handles the result.
    """
    def call(conn, %{auth_fn: auth_fn, error_handler: error_handler}) do
      case auth_fn.(conn) do
        {:ok, conn} ->
          conn
        
        {:error, reason} ->
          conn
          |> error_handler.(reason)
          |> halt()
      end
    end
    
    # Default error handler
    defp default_error_handler(conn, reason) do
      error_response = %{
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => %{
          "code" => -32001,
          "message" => "Authentication failed: #{reason}"
        }
      }
      
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(error_response))
    end
  end
end
