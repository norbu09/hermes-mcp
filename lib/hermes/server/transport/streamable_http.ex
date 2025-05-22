defmodule Hermes.Server.Transport.StreamableHTTP do
  @moduledoc """
  Streamable HTTP transport for Hermes MCP server.
  
  This module provides a server-side transport implementation that uses HTTP streaming
  for communication according to the latest MCP specification. It handles incoming
  HTTP requests and maintains a stream for sending responses back to clients.
  
  The streaming HTTP implementation supports:
  - Initial request/response for server initialization
  - Streaming responses for tool execution
  - Proper content negotiation with application/x-ndjson
  - Chunked transfer encoding
  
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
      
      # Start the Streamable HTTP transport
      {Hermes.Server.Transport.StreamableHTTP,
        name: MyApp.MCPTransport,
        server: MyApp.MCPServer,
        path: "/mcp/stream"
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
    
    # Forward MCP streaming requests to the Streamable HTTP transport
    forward "/mcp/stream", to: Hermes.Server.Transport.StreamableHTTP.Plug, 
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
    :connections,
    :request_handlers
  ]
  
  @type t :: GenServer.server()
  
  @type params_t :: Enumerable.t(option)
  
  @typedoc """
  The options for the Streamable HTTP transport.
  
  - `:name` - The name to register the transport process under (required)
  - `:server` - The name or PID of the server process (required)
  - `:path` - The path to serve streaming HTTP requests from (default: "/stream")
  """
  @type option ::
          {:name, GenServer.name()}
          | {:server, GenServer.server()}
          | {:path, String.t()}
          | GenServer.option()
  
  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    server: {:required, {:custom, &Hermes.genserver_name/1}},
    path: {:string, {:default, "/stream"}}
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
  Handles an HTTP request for the Streamable HTTP transport.
  
  This function is meant to be called from the StreamableHTTP.Plug module to handle
  streaming JSON-RPC requests over HTTP.
  """
  def handle_request(pid \\ __MODULE__, conn) do
    GenServer.call(pid, {:handle_request, conn})
  end
  
  @doc """
  Registers a new streaming connection.
  
  This function is meant to be called from the StreamableHTTP.Plug module when a new
  streaming connection is established.
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
    
    Logging.transport_event("streamable_http_init", "Initialized Streamable HTTP transport")
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:send, client_id, message}, _from, state) do
    case Map.get(state.connections, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}
      
      conn_pid ->
        metadata = %{
          transport: :streamable_http,
          message_size: byte_size(message),
          client_id: client_id
        }
        
        Telemetry.execute(
          Telemetry.event_transport_send(),
          %{system_time: System.system_time()},
          metadata
        )
        
        # Send the message to the connection handler
        send(conn_pid, {:send_chunk, message})
        
        {:reply, :ok, state}
    end
  end
  
  def handle_call({:broadcast, message}, _from, state) do
    metadata = %{
      transport: :streamable_http,
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
      send(conn_pid, {:send_chunk, message})
    end
    
    {:reply, :ok, state}
  end
  
  def handle_call({:close_connection, client_id}, _from, state) do
    case Map.get(state.connections, client_id) do
      nil ->
        {:reply, {:error, :client_not_found}, state}
      
      conn_pid ->
        # Send a close message to the connection handler
        send(conn_pid, :close)
        
        # Remove the connection from the state
        connections = Map.delete(state.connections, client_id)
        
        {:reply, :ok, %{state | connections: connections}}
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
        
        # Check if this is a streaming request
        is_streaming = 
          request["method"] == "tools/execute" or 
          request["method"] == "mcp/tools/execute"
        
        # Create a context for the request
        context = Context.new(
          connection_pid: self(),
          request_id: request_id,
          plug_conn: conn,
          custom_data: %{
            client_id: client_id,
            streaming: is_streaming and supports_streaming(conn)
          }
        )
        
        # Add the request handler to the state
        request_handlers = Map.put(state.request_handlers, client_id, handler_pid)
        state = %{state | request_handlers: request_handlers}
        
        # Process the request
        case Hermes.Server.process_request(state.server, request, context) do
          {:ok, response} ->
            # Send the response
            conn = conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, JSON.encode!(response))
            |> Plug.Conn.halt()
            
            {:reply, {:ok, conn}, state}
          
          {:error, error} ->
            # Send the error response
            error_response = %{
              "jsonrpc" => "2.0",
              "id" => request_id,
              "error" => error
            }
            
            conn = conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, JSON.encode!(error_response))
            |> Plug.Conn.halt()
            
            {:reply, {:ok, conn}, state}
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
        
        conn = conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, JSON.encode!(error_response))
        |> Plug.Conn.halt()
        
        {:reply, {:ok, conn}, state}
    end
  end
  
  def handle_call({:register_connection, _conn, client_id}, {conn_pid, _}, state) do
    Logging.transport_event("streamable_http_connection", "New streaming connection: #{client_id}")
    
    # Add the connection to the state
    connections = Map.put(state.connections, client_id, conn_pid)
    
    # Monitor the connection process
    Process.monitor(conn_pid)
    
    {:reply, :ok, %{state | connections: connections}}
  end
  
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Find the client ID for the connection
    client_id = Enum.find_value(state.connections, fn {id, conn_pid} ->
      if conn_pid == pid, do: id, else: nil
    end)
    
    if client_id do
      Logging.transport_event("streamable_http_disconnect", "Streaming connection closed: #{client_id}, reason: #{inspect(reason)}")
      
      # Remove the connection from the state
      connections = Map.delete(state.connections, client_id)
      
      {:noreply, %{state | connections: connections}}
    else
      # Check if it's a request handler
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
  end
  
  @impl GenServer
  def handle_cast(:shutdown, state) do
    # Close all connections
    for {_client_id, conn_pid} <- state.connections do
      send(conn_pid, :close)
    end
    
    {:stop, :normal, state}
  end
  
  # Check if the client supports streaming
  defp supports_streaming(conn) do
    case Plug.Conn.get_req_header(conn, "accept") do
      [accept] -> String.contains?(accept, "application/x-ndjson")
      _ -> false
    end
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

defmodule Hermes.Server.Transport.StreamableHTTP.Plug do
  @moduledoc """
  Plug for handling streamable HTTP requests.
  
  This plug handles JSON-RPC requests over HTTP with streaming responses
  according to the latest MCP specification.
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
    # Check if this is a streaming request
    case get_req_header(conn, "accept") do
      ["application/x-ndjson"] ->
        # This is a streaming request
        handle_streaming_request(conn, transport)
      
      _ ->
        # This is a regular request
        handle_regular_request(conn, transport)
    end
  end
  
  # Handle a streaming request
  defp handle_streaming_request(conn, transport) do
    client_id = get_client_id(conn)
    
    # Read the request body
    {:ok, body, conn} = read_body(conn)
    
    # Parse the JSON-RPC request
    case JSON.decode(body) do
      {:ok, request} ->
        # Generate a request ID if one wasn't provided
        request_id = Map.get(request, "id", Hermes.MCP.ID.generate())
        
        # Set up the streaming connection
        conn = conn
        |> put_resp_header("content-type", "application/x-ndjson")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("connection", "keep-alive")
        |> send_chunked(200)
        
        # Register the connection with the transport
        :ok = Hermes.Server.Transport.StreamableHTTP.register_connection(transport, conn, client_id)
        
        # Create a context for the request with streaming enabled
        context = Hermes.Server.Context.new(
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
        
        chunk(conn, JSON.encode!(initial_response) <> "\n")
        
        # Process the request (will send streaming responses)
        spawn(fn ->
          case Hermes.Server.process_request(transport.server, request, context) do
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
              
              send(self(), {:send_chunk, JSON.encode!(final_message)})
              
            {:error, error} ->
              # Send the error response
              error_message = %{
                "jsonrpc" => "2.0",
                "id" => request_id,
                "error" => error
              }
              
              send(self(), {:send_chunk, JSON.encode!(error_message)})
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
        |> send_resp(400, JSON.encode!(error_response))
    end
  end
  
  # Handle a regular request
  defp handle_regular_request(conn, transport) do
    # Forward the request to the transport
    case Hermes.Server.Transport.StreamableHTTP.handle_request(transport, conn) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
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
        
        case chunk(conn, JSON.encode!(progress_message) <> "\n") do
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
