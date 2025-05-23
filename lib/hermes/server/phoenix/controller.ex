defmodule Hermes.Server.Phoenix.Controller do
  @moduledoc """
  Phoenix controller for Hermes MCP server.

  This module provides a controller that can be used in Phoenix applications
  to handle MCP requests and delegate them to the appropriate server.

  ## Usage

  ```elixir
  defmodule MyAppWeb.MCPController do
    use Hermes.Server.Phoenix.Controller, server: MyApp.MCPServer
  end
  ```

  Then, in your router:

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

  require Logger

  @doc """
  Creates a new Phoenix controller for the specified MCP server.

  ## Options

  - `:server` - The name or PID of the server process (required)
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use Phoenix.Controller
      import Plug.Conn
      require Logger

      @server Keyword.fetch!(opts, :server)

      @doc """
      Handles MCP requests.

      This action handles JSON-RPC requests and delegates them to the MCP server.
      """
      def handle(conn, _params) do
        Logger.debug("Received JSON-RPC request")

        case read_request_body(conn) do
          {:ok, body, _conn} ->
            handle_json_rpc(conn, body)

          {:error, reason} ->
            conn
            |> send_resp(400, %{error: "Failed to read request body: #{reason}"})
        end
      end

      @doc """
      Handles streaming MCP requests.

      This action handles JSON-RPC requests and delegates them to the MCP server,
      with support for streaming responses.
      """
      def handle_stream(conn, _params) do
        Logger.debug("Received streaming JSON-RPC request")
        # Check if the client supports streaming
        # Read the request body
        case read_request_body(conn) do
          {:ok, request, conn} ->
            # Generate a request ID if one wasn't provided
            request_id = Map.get(request, "id", Hermes.MCP.ID.generate())
            client_id = get_client_id(conn)

            # Set up the streaming connection
            conn =
              conn
              |> put_resp_header("content-type", "application/x-ndjson")
              |> put_resp_header("cache-control", "no-cache")
              |> put_resp_header("connection", "keep-alive")
              |> send_chunked(200)

            # Create a context for the request with streaming enabled
            context =
              Hermes.Server.Context.new(
                connection_pid: self(),
                request_id: request_id,
                plug_conn: conn,
                custom_data: %{
                  client_id: client_id,
                  streaming: true
                }
              )

            # Send initial response to confirm connection
            initial_response = %{
              "jsonrpc" => "2.0",
              "id" => request_id,
              "result" => %{
                "status" => "streaming_started"
              }
            }

            chunk(conn, initial_response)

            # Process the request (will send streaming responses)
            spawn(fn ->
              case Hermes.Server.process_request(@server, request, context) do
                {:ok, final_response} ->
                  # Send the final response
                  final_message = %{
                    "jsonrpc" => "2.0",
                    "id" => request_id,
                    "result" => %{
                      "status" => "complete",
                      "data" => final_response
                    }
                  }

                  send(self(), {:send_chunk, final_message})

                {:error, error} ->
                  # Send the error response
                  error_message = %{
                    "jsonrpc" => "2.0",
                    "id" => request_id,
                    "error" => error
                  }

                  send(self(), {:send_chunk, error_message})
              end
            end)

            # Keep the connection open
            handle_streaming_connection(conn)

          {:error, _reason} ->
            # Send a parse error response
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => nil,
              "error" => %{
                "code" => -32700,
                "message" => "Parse error"
              }
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, error_response)
        end
      end

      # Handle the streaming connection
      defp handle_streaming_connection(conn) do
        receive do
          {:send_chunk, data} ->
            # Send the chunk to the client
            case chunk(conn, data <> "\n") do
              {:ok, conn} ->
                # Continue handling the connection
                handle_streaming_connection(conn)

              {:error, _reason} ->
                # Connection closed
                conn
            end

          {:send_progress, progress} ->
            # Send a progress update
            progress_message = %{
              "jsonrpc" => "2.0",
              "method" => "progress",
              "params" => progress
            }

            case chunk(conn, progress_message) do
              {:ok, conn} ->
                # Continue handling the connection
                handle_streaming_connection(conn)

              {:error, _reason} ->
                # Connection closed
                conn
            end

          :close ->
            # Close the connection
            conn
        end
      end

      # Handle JSON-RPC request
      defp handle_json_rpc(conn, request) do
        # Generate a request ID if one wasn't provided
        request_id = Map.get(request, "id", Hermes.MCP.ID.generate())

        # Create a context for the request
        context =
          Hermes.Server.Context.new(
            connection_pid: self(),
            request_id: request_id,
            plug_conn: conn
          )

        # Process the request
        case Hermes.Server.process_request(@server, request, context) do
          {:ok, result} ->
            # Send the response
            dbg(result)

            response = %{
              "jsonrpc" => "2.0",
              "id" => request_id,
              "result" => result
            }

            conn
            |> put_status(200)
            |> json(response)

          {:error, error} ->
            # Send the error response
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => request_id,
              "error" => error
            }

            conn
            |> put_status(200)
            |> json(error_response)
        end
      end

      # Read the request body
      defp read_request_body(conn) do
        dbg(conn)

        case conn.body_params do
          %Plug.Conn.Unfetched{} ->
            # Body not yet fetched, read it
            Plug.Conn.read_body(conn)

          params ->
            # Body already fetched, get it from the private field
            {:ok, params || "", conn}
        end
      end

      # Get the client ID from the connection
      defp get_client_id(conn) do
        # Try to get the client ID from the headers
        case get_req_header(conn, "x-client-id") do
          [client_id | _] ->
            client_id

          [] ->
            # Generate a client ID if one wasn't provided
            "client_#{System.unique_integer([:positive])}"
        end
      end
    end
  end
end
