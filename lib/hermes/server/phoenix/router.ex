defmodule Hermes.Server.Phoenix.Router do
  @moduledoc """
  Router macros for Hermes MCP server.
  
  This module provides macros that can be used in Phoenix routers
  to define MCP endpoints.
  
  ## Usage
  
  ```elixir
  defmodule MyAppWeb.Router do
    use Phoenix.Router
    import Hermes.Server.Phoenix.Router
    
    pipeline :api do
      plug :accepts, ["json"]
    end
    
    scope "/api" do
      pipe_through :api
      
      mcp_endpoints "/mcp", MyAppWeb.MCPController
    end
  end
  ```
  """
  
  @doc """
  Defines MCP endpoints for the specified controller.
  
  This macro defines the following routes:
  
  - `POST /path` - For handling JSON-RPC requests
  - `POST /path/stream` - For handling streaming JSON-RPC requests
  
  ## Parameters
  
  - `path` - The base path for the MCP endpoints
  - `controller` - The controller module that will handle the requests
  - `opts` - Additional options to pass to the Phoenix router
  """
  defmacro mcp_endpoints(path, controller, opts \\ []) do
    quote bind_quoted: [path: path, controller: controller, opts: opts] do
      # Regular JSON-RPC endpoint
      post path, controller, :handle, opts
      
      # Streaming JSON-RPC endpoint
      post "#{path}/stream", controller, :handle_stream, opts
    end
  end
end
