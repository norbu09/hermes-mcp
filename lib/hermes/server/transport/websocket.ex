defmodule Hermes.Server.Transport.WebSocket do
  @moduledoc """
  WebSocket transport for Hermes MCP server.
  
  This module provides a server-side transport implementation that uses WebSockets
  for bidirectional communication. It handles incoming WebSocket connections and
  maintains them for sending and receiving messages.
  
  ## Usage
  
  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # Start the HTTP server (e.g., Plug.Cowboy)
      {Plug.Cowboy, 
        scheme: :http, 
        plug: MyApp.Router, 
        options: [
          port: 4000,
          dispatch: [
            {:_, [
              {"/mcp/ws", Hermes.Server.Transport.WebSocket.Handler, 
                %{transport: MyApp.MCPTransport}},
              {:_, Plug.Cowboy.Handler, {MyApp.Router, []}}
            ]}
          ]
        ]
      },
      
      # Start the MCP Server
      {Hermes.Server,
        name: MyApp.MCPServer,
        server_name: "My MCP Server",
        version: "1.0.0",
        module_prefix: MyApp.MCP
      },
      
      # Start the WebSocket transport
      {Hermes.Server.Transport.WebSocket,
        name: MyApp.MCPTransport,
        server: MyApp.MCPServer,
        path: "/mcp/ws"
      }
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
  ```
  """
  
  @behaviour Hermes.Server.Transport.Behaviour
  
  use GenServer
  require Logger
  
  import Peri
  
  # Using ID in handle_call for request_id
  alias Hermes.Server.Context
  alias Hermes.Logging
  alias Hermes.Telemetry
  
  # Transport state
  defstruct [
    :name,
    :server,
    :path,
    :connections
  ]
  
  @type t :: GenServer.server()
  
  @type params_t :: Enumerable.t(option)
  
  @typedoc """
  The options for the WebSocket transport.
  
  - `:name` - The name to register the transport process under (required)
  - `:server` - The name or PID of the server process (required)
  - `:path` - The path to serve WebSocket connections from (default: "/ws")
  """
  @type option ::
          {:name, GenServer.name()}
          | {:server, GenServer.server()}
          | {:path, String.t()}
          | GenServer.option()
  
  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    server: {:required, {:custom, &Hermes.genserver_name/1}},
    path: {:string, {:default, "/ws"}}
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
  Registers a new WebSocket connection.
  
  This function is meant to be called from the WebSocket.Handler module when a new
  WebSocket connection is established.
  """
  def register_connection(pid \\ __MODULE__, ws_pid, client_id) do
    GenServer.call(pid, {:register_connection, ws_pid, client_id})
  end
  
  @doc """
  Handles a message received from a WebSocket connection.
  
  This function is meant to be called from the WebSocket.Handler module when a
  message is received from a client.
  """
  def handle_message(pid \\ __MODULE__, client_id, message) do
    GenServer.call(pid, {:handle_message, client_id, message})
  end
  
  @doc """
  Unregisters a WebSocket connection.
  
  This function is meant to be called from the WebSocket.Handler module when a
  WebSocket connection is closed.
  """
  def unregister_connection(pid \\ __MODULE__, client_id) do
    GenServer.cast(pid, {:unregister_connection, client_id})
  end
  
  @impl GenServer
  def init(%{} = opts) do
    state = %__MODULE__{
      name: opts.name,
      server: opts.server,
      path: opts.path,
      connections: %{}
    }
    
    Logging.transport_event("websocket_init", "Initialized WebSocket transport")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:send, client_id, message}, _from, state) do
    case Map.get(state.connections, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}
      
      ws_pid ->
        metadata = %{
          transport: :websocket,
          message_size: byte_size(message),
          client_id: client_id
        }
        
        Telemetry.execute(
          Telemetry.event_transport_send(),
          %{system_time: System.system_time()},
          metadata
        )
        
        # Send the message to the WebSocket handler
        send(ws_pid, {:send, message})
        
        {:reply, :ok, state}
    end
  end
  
  def handle_call({:broadcast, message}, _from, state) do
    metadata = %{
      transport: :websocket,
      message_size: byte_size(message),
      client_count: map_size(state.connections)
    }
    
    Telemetry.execute(
      Telemetry.event_transport_send(),
      %{system_time: System.system_time()},
      metadata
    )
    
    # Broadcast the message to all connections
    for {_client_id, ws_pid} <- state.connections do
      send(ws_pid, {:send, message})
    end
    
    {:reply, :ok, state}
  end
  
  def handle_call({:close_connection, client_id}, _from, state) do
    case Map.get(state.connections, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}
      
      ws_pid ->
        # Send a close message to the WebSocket handler
        send(ws_pid, :close)
        
        # Remove the connection from the state
        connections = Map.delete(state.connections, client_id)
        
        {:reply, :ok, %{state | connections: connections}}
    end
  end
  
  def handle_call({:register_connection, ws_pid, client_id}, _from, state) do
    Logging.transport_event("websocket_connection", "New WebSocket connection: #{client_id}")
    
    # Add the connection to the state
    connections = Map.put(state.connections, client_id, ws_pid)
    
    # Monitor the WebSocket process
    Process.monitor(ws_pid)
    
    {:reply, :ok, %{state | connections: connections}}
  end
  
  def handle_call({:handle_message, client_id, message}, _from, state) do
    metadata = %{
      transport: :websocket,
      message_size: byte_size(message),
      client_id: client_id
    }
    
    Telemetry.execute(
      Telemetry.event_transport_receive(),
      %{system_time: System.system_time()},
      metadata
    )
    
    # Parse the JSON-RPC request
    case JSON.decode(message) do
      {:ok, request} ->
        # Create a context for the request
        context = Context.new(
          connection_pid: self(),
          request_id: Map.get(request, "id"),
          custom_data: %{client_id: client_id}
        )
        
        # Process the request
        case Hermes.Server.process_request(state.server, request, context) do
          {:ok, response} ->
            # Send the response
            response_json = JSON.encode!(response)
            
            case Map.get(state.connections, client_id) do
              nil ->
                {:reply, {:error, :client_not_found}, state}
              
              ws_pid ->
                send(ws_pid, {:send, response_json})
                {:reply, :ok, state}
            end
          
          {:error, error} ->
            # Send the error response
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => Map.get(request, "id"),
              "error" => error
            }
            
            response_json = JSON.encode!(error_response)
            
            case Map.get(state.connections, client_id) do
              nil ->
                {:reply, {:error, :client_not_found}, state}
              
              ws_pid ->
                send(ws_pid, {:send, response_json})
                {:reply, :ok, state}
            end
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
        
        response_json = JSON.encode!(error_response)
        
        case Map.get(state.connections, client_id) do
          nil ->
            {:reply, {:error, :client_not_found}, state}
          
          ws_pid ->
            send(ws_pid, {:send, response_json})
            {:reply, :ok, state}
        end
    end
  end
  
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find the client ID for the connection
    client_id = Enum.find_value(state.connections, fn {id, ws_pid} ->
      if ws_pid == pid, do: id, else: nil
    end)
    
    if client_id do
      Logging.transport_event("websocket_disconnect", "WebSocket connection closed: #{client_id}, reason: #{inspect(reason)}")
      
      # Remove the connection from the state
      connections = Map.delete(state.connections, client_id)
      
      {:noreply, %{state | connections: connections}}
    else
      {:noreply, state}
    end
  end
  
  @impl GenServer
  def handle_cast({:unregister_connection, client_id}, state) do
    Logging.transport_event("websocket_disconnect", "WebSocket connection unregistered: #{client_id}")
    
    # Remove the connection from the state
    connections = Map.delete(state.connections, client_id)
    
    {:noreply, %{state | connections: connections}}
  end
  
  def handle_cast(:shutdown, state) do
    # Close all connections
    for {_client_id, ws_pid} <- state.connections do
      send(ws_pid, :close)
    end
    
    {:stop, :normal, state}
  end
  
end

defmodule Hermes.Server.Transport.WebSocket.Handler do
  @moduledoc """
  WebSocket handler for the WebSocket transport.
  
  This module handles the WebSocket protocol and forwards messages to the
  WebSocket transport for processing.
  """
  
  # This module implements the cowboy_websocket behavior
  # but we don't explicitly use @behaviour to avoid compile-time
  # dependencies on cowboy when it might not be available
  
  # @impl :cowboy_websocket
  def init(req, state) do
    {:cowboy_websocket, req, state}
  end
  
  # @impl :cowboy_websocket
  def websocket_init(state) do
    transport = Map.fetch!(state, :transport)
    client_id = get_client_id(state)
    
    # Register the connection with the transport
    :ok = Hermes.Server.Transport.WebSocket.register_connection(transport, self(), client_id)
    
    # Send a welcome message
    welcome = %{
      "jsonrpc" => "2.0",
      "method" => "connected",
      "params" => %{
        "client_id" => client_id
      }
    }
    
    {:reply, {:text, JSON.encode!(welcome)}, Map.put(state, :client_id, client_id)}
  end
  
  # @impl :cowboy_websocket
  def websocket_handle({:text, message}, state) do
    transport = Map.fetch!(state, :transport)
    client_id = Map.fetch!(state, :client_id)
    
    # Handle the message
    :ok = Hermes.Server.Transport.WebSocket.handle_message(transport, client_id, message)
    
    {:ok, state}
  end
  
  def websocket_handle(_frame, state) do
    {:ok, state}
  end
  
  # @impl :cowboy_websocket
  def websocket_info({:send, message}, state) do
    {:reply, {:text, message}, state}
  end
  
  def websocket_info(:close, state) do
    {:stop, state}
  end
  
  def websocket_info(_info, state) do
    {:ok, state}
  end
  
  # @impl :cowboy_websocket
  def terminate(_reason, _req, state) do
    transport = Map.fetch!(state, :transport)
    client_id = Map.fetch!(state, :client_id)
    
    # Unregister the connection
    Hermes.Server.Transport.WebSocket.unregister_connection(transport, client_id)
    
    :ok
  end
  
  # Get the client ID from the state or generate a new one
  defp get_client_id(state) do
    case Map.get(state, :client_id) do
      nil -> "client_#{System.unique_integer([:positive])}"
      client_id -> client_id
    end
  end
end
