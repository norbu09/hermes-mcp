defmodule Hermes.Server.Transport.SSE do
  @moduledoc """
  Server-Sent Events (SSE) transport for Hermes MCP server.
  
  This module provides a server-side transport implementation that uses HTTP and
  Server-Sent Events (SSE) for communication. It handles incoming HTTP requests
  and maintains SSE connections for sending events to clients.
  
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
      
      # Start the SSE transport
      {Hermes.Server.Transport.SSE,
        name: MyApp.MCPTransport,
        server: MyApp.MCPServer,
        path: "/mcp/sse"
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
    
    # Forward SSE requests to the SSE transport
    forward "/mcp/sse", to: Hermes.Server.Transport.SSE.Plug, 
      init_opts: [transport: MyApp.MCPTransport]
    
    # Handle JSON-RPC requests
    post "/mcp" do
      Hermes.Server.Transport.SSE.handle_request(MyApp.MCPTransport, conn)
    end
    
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
    :connections,
    :request_handlers
  ]
  
  @type t :: GenServer.server()
  
  @type params_t :: Enumerable.t(option)
  
  @typedoc """
  The options for the SSE transport.
  
  - `:name` - The name to register the transport process under (required)
  - `:server` - The name or PID of the server process (required)
  - `:path` - The path to serve SSE events from (default: "/sse")
  """
  @type option ::
          {:name, GenServer.name()}
          | {:server, GenServer.server()}
          | {:path, String.t()}
          | GenServer.option()
  
  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    server: {:required, {:custom, &Hermes.genserver_name/1}},
    path: {:string, {:default, "/sse"}}
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
  Handles an HTTP request for the SSE transport.
  
  This function is meant to be called from a Plug router to handle JSON-RPC
  requests over HTTP.
  """
  def handle_request(pid \\ __MODULE__, conn) do
    GenServer.call(pid, {:handle_request, conn})
  end
  
  @doc """
  Registers a new SSE connection.
  
  This function is meant to be called from the SSE.Plug module when a new
  SSE connection is established.
  """
  def register_connection(pid \\ __MODULE__, conn, client_id) do
    GenServer.call(pid, {:register_connection, conn, client_id})
  end
  
  @impl GenServer
  def init(%{} = opts) do
    state = %__MODULE__{
      name: opts.name,
      server: opts.server,
      path: opts.path,
      connections: %{},
      request_handlers: %{}
    }
    
    Logging.transport_event("sse_init", "Initialized SSE transport")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:send, client_id, message}, _from, state) do
    case Map.get(state.connections, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}
      
      conn_pid ->
        metadata = %{
          transport: :sse,
          message_size: byte_size(message),
          client_id: client_id
        }
        
        Telemetry.execute(
          Telemetry.event_transport_send(),
          %{system_time: System.system_time()},
          metadata
        )
        
        # Send the message as an SSE event
        send(conn_pid, {:send_event, %{
          event: "message",
          data: message
        }})
        
        {:reply, :ok, state}
    end
  end
  
  def handle_call({:broadcast, message}, _from, state) do
    metadata = %{
      transport: :sse,
      message_size: byte_size(message),
      client_count: map_size(state.connections)
    }
    
    Telemetry.execute(
      Telemetry.event_transport_send(),
      %{system_time: System.system_time()},
      metadata
    )
    
    # Broadcast the message to all connections
    for {_client_id, conn_pid} <- state.connections do
      send(conn_pid, {:send_event, %{
        event: "message",
        data: message
      }})
    end
    
    {:reply, :ok, state}
  end
  
  def handle_call({:close_connection, client_id}, _from, state) do
    case Map.get(state.connections, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}
      
      conn_pid ->
        # Send a close event to the connection
        send(conn_pid, :close)
        
        # Remove the connection from the state
        connections = Map.delete(state.connections, client_id)
        
        {:reply, :ok, %{state | connections: connections}}
    end
  end
  
  def handle_call({:handle_request, conn}, _from, state) do
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
        
        # Process the request
        case Hermes.Server.process_request(state.server, request, context) do
          {:ok, response} ->
            # Send the response
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, JSON.encode!(response))
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
  
  def handle_call({:register_connection, _conn, client_id}, {conn_pid, _}, state) do
    Logging.transport_event("sse_connection", "New SSE connection: #{client_id}")
    
    # Add the connection to the state
    connections = Map.put(state.connections, client_id, conn_pid)
    
    # Monitor the connection process
    Process.monitor(conn_pid)
    
    # Send a welcome event
    send(conn_pid, {:send_event, %{
      event: "connected",
      data: %{client_id: client_id} |> JSON.encode!()
    }})
    
    {:reply, :ok, %{state | connections: connections}}
  end
  
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find the client ID for the connection
    client_id = Enum.find_value(state.connections, fn {id, conn_pid} ->
      if conn_pid == pid, do: id, else: nil
    end)
    
    if client_id do
      Logging.transport_event("sse_disconnect", "SSE connection closed: #{client_id}, reason: #{inspect(reason)}")
      
      # Remove the connection from the state
      connections = Map.delete(state.connections, client_id)
      
      {:noreply, %{state | connections: connections}}
    else
      {:noreply, state}
    end
  end
  
  @impl GenServer
  def handle_cast(:shutdown, state) do
    # Close all connections
    for {_client_id, conn_pid} <- state.connections do
      send(conn_pid, :close)
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

defmodule Hermes.Server.Transport.SSE.Plug do
  @moduledoc """
  Plug for handling SSE connections.
  
  This plug handles the initial SSE connection and maintains it for
  sending events to the client.
  """
  
  import Plug.Conn
  
  @behaviour Plug
  
  @impl Plug
  def init(opts) do
    transport = Keyword.fetch!(opts, :transport)
    %{transport: transport}
  end
  
  @impl Plug
  def call(conn, %{transport: transport}) do
    client_id = get_client_id(conn)
    
    conn = conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
    
    # Register the connection with the transport
    :ok = Hermes.Server.Transport.SSE.register_connection(transport, conn, client_id)
    
    # Keep the connection open
    handle_sse_connection(conn)
  end
  
  # Handle the SSE connection
  defp handle_sse_connection(conn) do
    receive do
      {:send_event, event} ->
        # Send the event to the client
        event_data = format_sse_event(event)
        
        case chunk(conn, event_data) do
          {:ok, conn} ->
            # Continue handling the connection
            handle_sse_connection(conn)
          
          {:error, _reason} ->
            # Connection closed
            conn
        end
      
      :close ->
        # Close the connection
        conn
    end
  end
  
  # Format an event as an SSE event
  defp format_sse_event(%{event: event, data: data}) do
    "event: #{event}\ndata: #{data}\n\n"
  end
  
  # Get the client ID from the connection
  defp get_client_id(conn) do
    # Try to get the client ID from the headers
    case get_req_header(conn, "x-client-id") do
      [client_id | _] -> client_id
      [] -> 
        # Generate a client ID if one wasn't provided
        "client_#{System.unique_integer([:positive])}"
    end
  end
end
