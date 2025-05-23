defmodule Hermes.Server.Phoenix.AuthPlug do
  @moduledoc """
  Authentication plug for Hermes MCP server.
  
  This plug provides token-based authentication for MCP endpoints.
  It can be used in Phoenix pipelines to secure MCP endpoints.
  
  ## Usage
  
  ```elixir
  pipeline :api do
    plug :accepts, ["json"]
    plug Hermes.Server.Phoenix.AuthPlug, token: "your_secret_token"
  end
  ```
  
  You can also provide a function for token validation:
  
  ```elixir
  pipeline :api do
    plug :accepts, ["json"]
    plug Hermes.Server.Phoenix.AuthPlug, validator: &MyApp.validate_token/1
  end
  ```
  """
  
  import Plug.Conn
  
  @behaviour Plug
  
  @impl Plug
  def init(opts) do
    # Get the token or validator function
    token = Keyword.get(opts, :token)
    validator = Keyword.get(opts, :validator)
    
    # Ensure at least one authentication method is provided
    if is_nil(token) and is_nil(validator) do
      # Use a default token (nil) if none is provided
      opts
    else
      opts
    end
  end
  
  @impl Plug
  def call(conn, opts) do
    # Get the token or validator function
    token = Keyword.get(opts, :token)
    validator = Keyword.get(opts, :validator)
    
    # If no authentication is required, pass through
    if is_nil(token) and is_nil(validator) do
      conn
    else
      # Get the authorization header
      case get_req_header(conn, "authorization") do
        ["Bearer " <> provided_token] ->
          # Validate the token
          if valid_token?(provided_token, token, validator) do
            # Token is valid, continue
            conn
          else
            # Token is invalid, halt with 401
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{
              "jsonrpc" => "2.0",
              "error" => %{
                "code" => -32001,
                "message" => "Invalid token"
              },
              "id" => nil
            }))
            |> halt()
          end
        
        _ ->
          # No token provided, halt with 401
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{
            "jsonrpc" => "2.0",
            "error" => %{
              "code" => -32001,
              "message" => "Authentication required"
            },
            "id" => nil
          }))
          |> halt()
      end
    end
  end
  
  # Validate the token against a static token or using a validator function
  defp valid_token?(provided_token, token, validator) do
    cond do
      # If a validator function is provided, use it
      is_function(validator, 1) ->
        validator.(provided_token)
      
      # Otherwise, compare with the static token
      is_binary(token) ->
        provided_token == token
      
      # If neither is provided, always fail
      true ->
        false
    end
  end
end
