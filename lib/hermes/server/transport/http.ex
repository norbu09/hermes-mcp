defmodule Hermes.Server.Transport.HTTP do
  @moduledoc """
  HTTP transport for Hermes MCP server.

  This module provides a server-side transport implementation that uses HTTP for
  communication. It handles incoming HTTP requests and sends responses back to
  clients.

  ## Usage

  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # Start the HTTP server (e.g., Plug.Cowboy)
      {Plug.Cowboy, scheme: :http, plug: MyApp.Router, options: [port: 4000]},

      # Start the MCP Server
      {Hermes.Server,
        name: MyApp.MCPServer,
        server_name: "My MCP Server",
        version: "1.0.0",
        module_prefix: MyApp.MCP
      },

      # Start the HTTP transport
      {Hermes.Server.Transport.HTTP,
        name: MyApp.MCPTransport,
        server: MyApp.MCPServer,
        path: "/mcp"
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
  ```

  Then, in your router:

  ```elixir
  defmodule MyApp.Router do
    use Plug.Router

    plug :match
    plug :dispatch

    # Forward MCP requests to the HTTP transport
    forward "/mcp", to: Hermes.Server.Transport.HTTP.Plug,
      init_opts: [transport: MyApp.MCPTransport]

    match _ do
      send_resp(conn, 404, "Not found")
    end
  end
  ```
  """

  @behaviour Hermes.Server.Transport.Behaviour

  use GenServer
  require Logger

  import Peri

  alias Hermes.MCP.ID
  alias Hermes.Server.Context
  alias Hermes.Logging
  alias Hermes.Telemetry

  # Transport state
  defstruct [
    :name,
    :server,
    :path,
    :request_handlers
  ]

  @type t :: GenServer.server()

  @type params_t :: Enumerable.t(option)

  @typedoc """
  The options for the HTTP transport.

  - `:name` - The name to register the transport process under (required)
  - `:server` - The name or PID of the server process (required)
  - `:path` - The path to serve HTTP requests from (default: "/mcp")
  """
  @type option ::
          {:name, GenServer.name()}
          | {:server, GenServer.server()}
          | {:path, String.t()}
          | GenServer.option()

  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    server: {:required, {:custom, &Hermes.genserver_name/1}},
    path: {:string, {:default, "/mcp"}}
  })

  @impl Hermes.Server.Transport.Behaviour
  @spec start_link(params_t) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = options_schema!(opts)
    GenServer.start_link(__MODULE__, Map.new(opts), name: opts[:name])
  end

  @impl Hermes.Server.Transport.Behaviour
  def send_message(pid \\ __MODULE__, client_id, message) when is_binary(message) do
    GenServer.call(pid, {:send, client_id, message})
  end

  @impl Hermes.Server.Transport.Behaviour
  def broadcast_message(pid \\ __MODULE__, message) when is_binary(message) do
    GenServer.call(pid, {:broadcast, message})
  end

  @impl Hermes.Server.Transport.Behaviour
  def close_connection(pid \\ __MODULE__, client_id) do
    GenServer.call(pid, {:close_connection, client_id})
  end

  @impl Hermes.Server.Transport.Behaviour
  def shutdown(pid \\ __MODULE__) do
    GenServer.cast(pid, :shutdown)
  end

  @doc """
  Handles an HTTP request for the HTTP transport.

  This function is meant to be called from the HTTP.Plug module to handle
  JSON-RPC requests over HTTP.
  """
  def handle_request(pid \\ __MODULE__, conn) do
    GenServer.call(pid, {:handle_request, conn})
  end

  @impl GenServer
  def init(%{} = opts) do
    state = %__MODULE__{
      name: opts.name,
      server: opts.server,
      path: opts.path,
      request_handlers: %{}
    }

    Logging.transport_event("http_init", "Initialized HTTP transport")

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:send, client_id, message}, _from, state) do
    case Map.get(state.request_handlers, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      handler_pid ->
        metadata = %{
          transport: :http,
          message_size: byte_size(message),
          client_id: client_id
        }

        Telemetry.execute(
          Telemetry.event_transport_send(),
          %{system_time: System.system_time()},
          metadata
        )

        # Send the message to the request handler
        send(handler_pid, {:response, message})

        # Remove the request handler from the state
        request_handlers = Map.delete(state.request_handlers, client_id)

        {:reply, :ok, %{state | request_handlers: request_handlers}}
    end
  end

  def handle_call({:broadcast, _message}, _from, state) do
    # HTTP transport doesn't support broadcasting
    {:reply, {:error, :not_supported}, state}
  end

  def handle_call({:close_connection, client_id}, _from, state) do
    case Map.get(state.request_handlers, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}

      handler_pid ->
        # Send a close message to the request handler
        send(handler_pid, :close)

        # Remove the request handler from the state
        request_handlers = Map.delete(state.request_handlers, client_id)

        {:reply, :ok, %{state | request_handlers: request_handlers}}
    end
  end

  def handle_call({:handle_request, conn}, {handler_pid, _}, state) do
    # Read the request body
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    # Parse the JSON-RPC request
    case JSON.decode(body) do
      {:ok, request} ->
        # Generate a request ID if one wasn't provided
        request_id = Map.get(request, "id", ID.generate())
        client_id = get_client_id(conn)

        # Create a context for the request
        context = Context.new(
          connection_pid: self(),
          request_id: request_id,
          plug_conn: conn,
          custom_data: %{client_id: client_id}
        )

        # Add the request handler to the state
        request_handlers = Map.put(state.request_handlers, client_id, handler_pid)
        state = %{state | request_handlers: request_handlers}

        # Process the request
        case Hermes.Server.process_request(state.server, request, context) do
          {:ok, response} ->
            # Send the response
            response_json = JSON.encode!(response)

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, response_json)
            |> Plug.Conn.halt()
            |> (fn conn -> {:reply, {:ok, conn}, state} end).()

          {:error, error} ->
            # Send the error response
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => request_id,
              "error" => error
            }

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, JSON.encode!(error_response))
            |> Plug.Conn.halt()
            |> (fn conn -> {:reply, {:ok, conn}, state} end).()
        end

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
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, JSON.encode!(error_response))
        |> Plug.Conn.halt()
        |> (fn conn -> {:reply, {:ok, conn}, state} end).()
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Find the client ID for the request handler
    client_id = Enum.find_value(state.request_handlers, fn {id, handler_pid} ->
      if handler_pid == pid, do: id, else: nil
    end)

    if client_id do
      # Remove the request handler from the state
      request_handlers = Map.delete(state.request_handlers, client_id)

      {:noreply, %{state | request_handlers: request_handlers}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:shutdown, state) do
    # Close all request handlers
    for {_client_id, handler_pid} <- state.request_handlers do
      send(handler_pid, :close)
    end

    {:stop, :normal, state}
  end

  # Get the client ID from the connection
  defp get_client_id(conn) do
    # Try to get the client ID from the headers
    case Plug.Conn.get_req_header(conn, "x-client-id") do
      [client_id | _] -> client_id
      [] ->
        # Generate a client ID if one wasn't provided
        "client_#{System.unique_integer([:positive])}"
    end
  end


end
