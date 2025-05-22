defmodule Hermes.Server.Transport.STDIO do
  @moduledoc """
  STDIO transport for Hermes MCP server.
  
  This module provides a server-side transport implementation that uses standard input
  and output for communication. It reads JSON-RPC messages from standard input
  and writes responses to standard output.
  
  ## Usage
  
  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # Start the MCP Server
      {Hermes.Server,
        name: MyApp.MCPServer,
        server_name: "My MCP Server",
        version: "1.0.0",
        module_prefix: MyApp.MCP
      },
      
      # Start the STDIO transport
      {Hermes.Server.Transport.STDIO,
        name: MyApp.MCPTransport,
        server: MyApp.MCPServer
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
  
  # We don't need these aliases as we're not using them directly
  alias Hermes.Server.Context
  alias Hermes.Logging
  alias Hermes.Telemetry
  
  # Transport state
  defstruct [
    :name,
    :server,
    :input_device,
    :output_device,
    :buffer,
    :encoding,
    :client_id,
    :port
  ]
  
  @type t :: GenServer.server()
  
  @type params_t :: Enumerable.t(option)
  
  @typedoc """
  The options for the STDIO transport.
  
  - `:name` - The name to register the transport process under (required)
  - `:server` - The name or PID of the server process (required)
  - `:input_device` - The input device (default: :stdio)
  - `:output_device` - The output device (default: :stdio)
  - `:encoding` - The encoding to use for input/output (default: :utf8)
  - `:command` - The command to run (optional)
  - `:args` - The arguments to pass to the command (optional)
  - `:env` - The environment variables to pass to the command (optional)
  - `:cwd` - The working directory for the command (optional)
  """
  @type option ::
          {:name, GenServer.name()}
          | {:server, GenServer.server()}
          | {:input_device, :stdio | File.io_device()}
          | {:output_device, :stdio | File.io_device()}
          | {:encoding, :utf8 | :latin1 | :unicode}
          | {:command, String.t() | nil}
          | {:args, [String.t()] | nil}
          | {:env, map() | nil}
          | {:cwd, String.t() | nil}
          | GenServer.option()
  
  defschema(:options_schema, %{
    name: {{:custom, &Hermes.genserver_name/1}, {:default, __MODULE__}},
    server: {:required, {:custom, &Hermes.genserver_name/1}},
    input_device: {:any, {:default, :stdio}},
    output_device: {:any, {:default, :stdio}},
    encoding: {:atom, {:default, :utf8}},
    command: {:string, {:default, nil}},
    args: {{:list, :string}, {:default, nil}},
    env: {:map, {:default, nil}},
    cwd: {:string, {:default, nil}}
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
  
  @impl GenServer
  def init(%{} = opts) do
    state = %__MODULE__{
      name: opts.name,
      server: opts.server,
      input_device: opts.input_device,
      output_device: opts.output_device,
      buffer: "",
      encoding: opts.encoding,
      client_id: "stdio_client"
    }
    
    if opts.command do
      # If a command is provided, spawn a port to run it
      {:ok, state, {:continue, {:spawn_command, opts}}}
    else
      # Otherwise, start reading from input directly
      {:ok, state, {:continue, :start_reading}}
    end
  end
  
  @impl GenServer
  def handle_continue({:spawn_command, opts}, state) do
    if cmd = System.find_executable(opts.command) do
      port = spawn_port(cmd, opts)
      _ref = Port.monitor(port)
      
      metadata = %{
        transport: :stdio,
        command: opts.command,
        args: opts.args
      }
      
      Telemetry.execute(
        Telemetry.event_transport_init(),
        %{system_time: System.system_time()},
        metadata
      )
      
      {:noreply, %{state | port: port}}
    else
      Logger.error("Command not found: #{opts.command}")
      {:stop, {:error, "Command not found: #{opts.command}"}, state}
    end
  end
  
  def handle_continue(:start_reading, state) do
    Process.send_after(self(), :read_input, 0)
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_call({:send, client_id, message}, _from, state) do
    if client_id == state.client_id do
      metadata = %{
        transport: :stdio,
        message_size: byte_size(message),
        client_id: client_id
      }
      
      Telemetry.execute(
        Telemetry.event_transport_send(),
        %{system_time: System.system_time()},
        metadata
      )
      
      if is_port(state.port) do
        Port.command(state.port, message)
      else
        IO.write(state.output_device, message)
      end
      
      {:reply, :ok, state}
    else
      {:reply, {:error, :client_not_found}, state}
    end
  end
  
  def handle_call({:broadcast, message}, _from, state) do
    # For STDIO, broadcast is the same as send to the single client
    handle_call({:send, state.client_id, message}, nil, state)
  end
  
  def handle_call({:close_connection, client_id}, _from, state) do
    if client_id == state.client_id do
      if is_port(state.port) do
        Port.close(state.port)
      end
      
      {:reply, :ok, state}
    else
      {:reply, {:error, :client_not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_info(:read_input, state) do
    case IO.read(state.input_device, :line) do
      :eof ->
        # End of input, terminate
        Logging.transport_event("stdio_eof", "End of input, terminating")
        {:stop, :normal, state}
      
      {:error, reason} ->
        # Error reading from input
        Logging.transport_event("stdio_error", "Error reading from input: #{inspect(reason)}", level: :error)
        {:stop, {:error, reason}, state}
      
      data ->
        # Process the input data
        Logging.transport_event("stdio_received", String.slice(data, 0, 100))
        
        Telemetry.execute(
          Telemetry.event_transport_receive(),
          %{system_time: System.system_time()},
          %{
            transport: :stdio,
            message_size: byte_size(data),
            client_id: state.client_id
          }
        )
        
        state = process_input(state, data)
        
        # Continue reading from input
        Process.send_after(self(), :read_input, 0)
        
        {:noreply, state}
    end
  end
  
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logging.transport_event("stdio_received", String.slice(data, 0, 100))
    
    Telemetry.execute(
      Telemetry.event_transport_receive(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        message_size: byte_size(data),
        client_id: state.client_id
      }
    )
    
    state = process_input(state, data)
    {:noreply, state}
  end
  
  def handle_info({port, :closed}, %{port: port} = state) do
    Logging.transport_event("stdio_closed", "Port closed", level: :warning)
    
    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        reason: :normal,
        client_id: state.client_id
      }
    )
    
    {:stop, :normal, state}
  end
  
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logging.transport_event("stdio_exit", %{status: status}, level: :warning)
    
    Telemetry.execute(
      Telemetry.event_transport_error(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        error: :exit_status,
        status: status,
        client_id: state.client_id
      }
    )
    
    {:stop, {:exit, status}, state}
  end
  
  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logging.transport_event("stdio_down", %{reason: reason}, level: :warning)
    
    Telemetry.execute(
      Telemetry.event_transport_disconnect(),
      %{system_time: System.system_time()},
      %{
        transport: :stdio,
        reason: reason,
        client_id: state.client_id
      }
    )
    
    {:stop, {:port_down, reason}, state}
  end
  
  def handle_info({:send_response, response}, state) do
    # Convert response to JSON string
    response_json = JSON.encode!(response)
    
    # Send the response
    handle_call({:send, state.client_id, response_json <> "\n"}, nil, state)
  end
  
  @impl GenServer
  def handle_cast(:shutdown, state) do
    if is_port(state.port) do
      Port.close(state.port)
    end
    
    {:stop, :normal, state}
  end
  
  # Process input data
  defp process_input(state, data) do
    # Append data to buffer
    buffer = state.buffer <> data
    
    # Try to parse a complete JSON-RPC message
    case parse_message(buffer) do
      {:ok, message, rest} ->
        # Process the message
        process_message(state, message)
        
        # Continue with the rest of the buffer
        %{state | buffer: rest}
      
      {:error, :incomplete} ->
        # Not enough data to parse a complete message
        %{state | buffer: buffer}
      
      {:error, reason} ->
        # Error parsing the message
        Logging.transport_event("stdio_parse_error", "Error parsing message: #{inspect(reason)}", level: :error)
        
        # Send error response
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{
            "code" => -32700,
            "message" => "Parse error"
          }
        }
        
        send(self(), {:send_response, error_response})
        
        # Clear the buffer
        %{state | buffer: ""}
    end
  end
  
  # Parse a JSON-RPC message from the buffer
  defp parse_message(buffer) do
    case JSON.decode(buffer) do
      {:ok, message} ->
        # Successfully parsed a complete message
        {:ok, message, ""}
      
      {:error, %JSON.DecodeError{offset: nil}} ->
        # Empty buffer
        {:error, :incomplete}
      
      {:error, %JSON.DecodeError{}} ->
        # Try to find the end of the current message
        case find_message_end(buffer) do
          {:ok, message_json, rest} ->
            case JSON.decode(message_json) do
              {:ok, message} ->
                {:ok, message, rest}
              
              {:error, reason} ->
                {:error, reason}
            end
          
          {:error, :incomplete} ->
            {:error, :incomplete}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Find the end of a JSON-RPC message in the buffer
  defp find_message_end(buffer) do
    # This is a simplified implementation that assumes each message
    # is on a separate line. A more robust implementation would need
    # to parse the JSON structure to find the end of the message.
    case String.split(buffer, "\n", parts: 2) do
      [message, rest] ->
        {:ok, message, rest}
      
      [_] ->
        {:error, :incomplete}
    end
  end
  
  # Process a JSON-RPC message
  defp process_message(state, message) do
    # Create a context for the request
    context = Context.new(
      connection_pid: self(),
      request_id: message["id"],
      custom_data: %{client_id: state.client_id}
    )
    
    # Send the message to the server
    case Hermes.Server.process_request(state.server, message, context) do
      {:ok, response} ->
        # Send the response
        send(self(), {:send_response, response})
      
      {:error, error} ->
        # Send the error response
        error_response = %{
          "jsonrpc" => "2.0",
          "id" => message["id"],
          "error" => error
        }
        
        send(self(), {:send_response, error_response})
    end
  end
  
  # Spawn a port to run a command
  defp spawn_port(cmd, opts) do
    args = opts.args || []
    env = prepare_env(opts.env)
    cwd = opts.cwd
    
    Port.open(
      {:spawn_executable, cmd},
      [
        :binary,
        :exit_status,
        {:args, args},
        {:env, env},
        {:cd, cwd},
        {:line, 1024}
      ]
    )
  end
  
  # Prepare environment variables for the port
  defp prepare_env(nil), do: []
  defp prepare_env(env) when is_map(env) do
    Enum.map(env, fn {key, value} -> {to_charlist(key), to_charlist(value)} end)
  end
end
