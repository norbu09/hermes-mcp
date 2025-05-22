# Hermes MCP Server Implementation Guide

## Introduction

This guide provides a step-by-step approach to implementing the server-side component architecture for Hermes MCP. It builds on the implementation plan and technical specification to provide practical guidance for developers.

## Implementation Phases

### Phase 1: Core Behaviors

#### Step 1: Define the Tool Behavior

Create the `Hermes.Server.Tool` behavior that defines the interface for MCP tools.

```elixir
# lib/hermes/server/tool.ex
defmodule Hermes.Server.Tool do
  @moduledoc """
  Defines the behavior for MCP tools.
  """
  
  @doc "Returns the name of the tool."
  @callback name() :: String.t()
  
  @doc "Returns a description of the tool."
  @callback description() :: String.t()
  
  @doc "Returns the parameter schema for the tool."
  @callback parameters() :: [map()]
  
  @doc "Handles a tool execution request."
  @callback handle(params :: map(), context :: map()) ::
              {:ok, result :: any()} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0, parameters: 0]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Hermes.Server.Tool
      
      # Default implementations
      def name do
        module_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()
        module_name |> Macro.underscore() |> String.replace("_", "-")
      end
      
      def description do
        "Tool implemented by #{__MODULE__}"
      end
      
      def parameters do
        []
      end
      
      defoverridable [name: 0, description: 0, parameters: 0]
    end
  end
end
```

#### Step 2: Define the Resource Behavior

Create the `Hermes.Server.Resource` behavior that defines the interface for MCP resources.

```elixir
# lib/hermes/server/resource.ex
defmodule Hermes.Server.Resource do
  @moduledoc """
  Defines the behavior for MCP resources.
  """
  
  @doc "Returns the URI of the resource."
  @callback uri() :: String.t()
  
  @doc "Returns the name of the resource."
  @callback name() :: String.t()
  
  @doc "Returns a description of the resource."
  @callback description() :: String.t()
  
  @doc "Returns the MIME type of the resource."
  @callback mime_type() :: String.t()
  
  @doc "Reads the resource content."
  @callback read(params :: map(), context :: map()) ::
              {:ok, content :: binary() | String.t()} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Hermes.Server.Resource
      
      # Default implementations
      def name do
        module_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()
        module_name |> Macro.underscore() |> String.replace("_", "-")
      end
      
      def description do
        "Resource implemented by #{__MODULE__}"
      end
      
      defoverridable [name: 0, description: 0]
    end
  end
end
```

#### Step 3: Define the Prompt Behavior

Create the `Hermes.Server.Prompt` behavior that defines the interface for MCP prompts.

```elixir
# lib/hermes/server/prompt.ex
defmodule Hermes.Server.Prompt do
  @moduledoc """
  Defines the behavior for MCP prompts.
  """
  
  @doc "Returns the name of the prompt."
  @callback name() :: String.t()
  
  @doc "Returns a description of the prompt."
  @callback description() :: String.t()
  
  @doc "Returns the argument schema for the prompt."
  @callback arguments() :: [map()]
  
  @doc "Gets the prompt content."
  @callback get(args :: map(), context :: map()) ::
              {:ok, messages :: [map()]} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0, arguments: 0]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Hermes.Server.Prompt
      
      # Default implementations
      def name do
        module_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()
        module_name |> Macro.underscore() |> String.replace("_", "-")
      end
      
      def description do
        "Prompt implemented by #{__MODULE__}"
      end
      
      def arguments do
        []
      end
      
      defoverridable [name: 0, description: 0, arguments: 0]
    end
  end
end
```

#### Step 4: Define the Implementation Behavior

Create the `Hermes.Server.Implementation` behavior that defines the interface for MCP server implementations.

```elixir
# lib/hermes/server/implementation.ex
defmodule Hermes.Server.Implementation do
  @moduledoc """
  Defines the behavior for MCP server implementations.
  """
  
  @doc "Initializes the server state."
  @callback init(opts :: keyword()) ::
              {:ok, state :: term()} | {:stop, reason :: term()}
  
  @doc "Returns the server capabilities."
  @callback server_capabilities(conn :: term(), state :: term()) ::
              {:ok, capabilities :: map(), new_state :: term()}
  
  @doc "Handles client capabilities."
  @callback handle_client_capabilities(conn :: term(), capabilities :: map(), state :: term()) ::
              {:ok, new_state :: term()}
  
  @doc "Lists available resources."
  @callback list_resources(conn :: term(), params :: map(), state :: term()) ::
              {:reply, resources :: [map()], new_state :: term()}
  
  @doc "Gets a resource by ID."
  @callback get_resource(conn :: term(), id :: String.t(), params :: map(), state :: term()) ::
              {:reply, resource :: map(), new_state :: term()}
  
  @doc "Lists available prompts."
  @callback list_prompts(conn :: term(), params :: map(), state :: term()) ::
              {:reply, prompts :: [map()], new_state :: term()}
  
  @doc "Gets a prompt by ID."
  @callback get_prompt(conn :: term(), id :: String.t(), params :: map(), state :: term()) ::
              {:reply, prompt :: map(), new_state :: term()}
  
  @doc "Lists available tools."
  @callback list_tools(conn :: term(), params :: map(), state :: term()) ::
              {:reply, tools :: [map()], new_state :: term()}
  
  @doc "Executes a tool by ID."
  @callback execute_tool(conn :: term(), id :: String.t(), params :: map(), state :: term()) ::
              {:reply, result :: term(), new_state :: term()}
  
  @doc "Authorizes a request."
  @callback authorize(conn :: term(), method :: String.t(), params :: map(), state :: term()) ::
              {:ok, new_state :: term()} | {:error, error :: map(), new_state :: term()}
  
  @optional_callbacks [
    handle_client_capabilities: 3,
    authorize: 4
  ]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Hermes.Server.Implementation
      
      # Default implementations
      def handle_client_capabilities(_conn, _capabilities, state) do
        {:ok, state}
      end
      
      def authorize(_conn, _method, _params, state) do
        {:ok, state}
      end
      
      defoverridable [handle_client_capabilities: 3, authorize: 4]
    end
  end
end
```

### Phase 2: Server Implementation

#### Step 1: Create the Server Context

Create the `Hermes.Server.Context` module that defines the context for MCP server requests.

```elixir
# lib/hermes/server/context.ex
defmodule Hermes.Server.Context do
  @moduledoc """
  Defines the context for MCP server requests.
  """
  
  defstruct [
    :connection_pid,
    :client_capabilities,
    :plug_conn,
    :request_id,
    :auth_context,
    :authenticated,
    custom_data: %{}
  ]
  
  @type t :: %__MODULE__{
    connection_pid: pid(),
    client_capabilities: map() | nil,
    plug_conn: map() | nil,
    request_id: String.t() | nil,
    auth_context: map() | nil,
    authenticated: boolean(),
    custom_data: map()
  }
end
```

#### Step 2: Create the Server GenServer

Create the `Hermes.Server` module that provides the main server implementation.

```elixir
# lib/hermes/server/server.ex
defmodule Hermes.Server do
  @moduledoc """
  Main server implementation for Hermes MCP.
  """
  
  use GenServer
  require Logger
  
  alias Hermes.MCP.{Message, Error, ID}
  alias Hermes.Server.Context
  
  # Server state
  defstruct [
    :name,
    :version,
    :module_prefix,
    :tools,
    :resources,
    :prompts,
    :handler_module,
    :handler_state
  ]
  
  @doc """
  Starts the server GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  @impl GenServer
  def init(opts) do
    name = Keyword.get(opts, :name, "Hermes MCP Server")
    version = Keyword.get(opts, :version, "1.0.0")
    module_prefix = Keyword.get(opts, :module_prefix)
    
    # Initialize state
    state = %__MODULE__{
      name: name,
      version: version,
      module_prefix: module_prefix,
      tools: [],
      resources: [],
      prompts: []
    }
    
    # Discover components if module_prefix is provided
    state =
      if module_prefix do
        discover_components(state)
      else
        state
      end
    
    {:ok, state}
  end
  
  # Component discovery
  defp discover_components(state) do
    # TODO: Implement component discovery
    state
  end
  
  # Message handling
  @impl GenServer
  def handle_call({:process_request, method, params}, _from, state) do
    # TODO: Implement request processing
    {:reply, {:error, "Not implemented"}, state}
  end
end
```

#### Step 3: Create the Attribute Parser

Create the `Hermes.Server.AttributeParser` module that provides utilities for parsing module attributes.

```elixir
# lib/hermes/server/attribute_parser.ex
defmodule Hermes.Server.AttributeParser do
  @moduledoc """
  Utilities for parsing module attributes.
  """
  
  @doc """
  Extracts tool definitions from a module.
  """
  def extract_tools(module) do
    # TODO: Implement tool extraction
    []
  end
  
  @doc """
  Extracts resource definitions from a module.
  """
  def extract_resources(module) do
    # TODO: Implement resource extraction
    []
  end
  
  @doc """
  Extracts prompt definitions from a module.
  """
  def extract_prompts(module) do
    # TODO: Implement prompt extraction
    []
  end
  
  @doc """
  Parses a doc attribute for MCP metadata.
  """
  def parse_doc_attribute(doc) do
    # TODO: Implement doc attribute parsing
    %{}
  end
end
```

### Phase 3: Transport Implementations

#### Step 1: Create the STDIO Transport

Create the `Hermes.Server.Transport.STDIO` module that provides a transport implementation using standard input and output.

```elixir
# lib/hermes/server/transport/stdio.ex
defmodule Hermes.Server.Transport.STDIO do
  @moduledoc """
  STDIO transport for Hermes MCP server.
  """
  
  use GenServer
  require Logger
  
  alias Hermes.MCP.{Message, Error, ID}
  
  # Transport state
  defstruct [
    :server_pid,
    :input_device,
    :output_device
  ]
  
  @doc """
  Starts the STDIO transport.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  @impl GenServer
  def init(opts) do
    server_pid = Keyword.fetch!(opts, :server_pid)
    input_device = Keyword.get(opts, :input_device, :stdio)
    output_device = Keyword.get(opts, :output_device, :stdio)
    
    # Initialize state
    state = %__MODULE__{
      server_pid: server_pid,
      input_device: input_device,
      output_device: output_device
    }
    
    # Start reading from input
    Process.send_after(self(), :read_input, 0)
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_info(:read_input, state) do
    # TODO: Implement input reading
    {:noreply, state}
  end
end
```

#### Step 2: Create the HTTP/SSE Transport

Create the `Hermes.Server.Transport.SSE` module that provides a transport implementation using HTTP and Server-Sent Events.

```elixir
# lib/hermes/server/transport/sse.ex
defmodule Hermes.Server.Transport.SSE do
  @moduledoc """
  HTTP/SSE transport for Hermes MCP server.
  """
  
  use GenServer
  require Logger
  
  alias Hermes.MCP.{Message, Error, ID}
  
  # Transport state
  defstruct [
    :server_pid,
    :clients
  ]
  
  @doc """
  Starts the SSE transport.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  @impl GenServer
  def init(opts) do
    server_pid = Keyword.fetch!(opts, :server_pid)
    
    # Initialize state
    state = %__MODULE__{
      server_pid: server_pid,
      clients: %{}
    }
    
    {:ok, state}
  end
  
  @doc """
  Handles an HTTP request.
  """
  def handle_request(conn, transport_pid) do
    # TODO: Implement request handling
    conn
  end
end
```

### Phase 4: Phoenix Integration

#### Step 1: Create the MCP Controller

Create the `Hermes.Server.Phoenix.Controller` module that provides a controller for handling MCP requests in a Phoenix application.

```elixir
# lib/hermes/server/phoenix/controller.ex
defmodule Hermes.Server.Phoenix.Controller do
  @moduledoc """
  Phoenix controller for Hermes MCP server.
  """
  
  use Phoenix.Controller
  
  @doc """
  Handles JSON-RPC requests.
  """
  def handle_rpc(conn, params) do
    # TODO: Implement RPC handling
    conn
  end
  
  @doc """
  Handles SSE connections.
  """
  def handle_sse(conn, params) do
    # TODO: Implement SSE handling
    conn
  end
end
```

#### Step 2: Create the MCP Router

Create the `Hermes.Server.Phoenix.Router` module that provides macros for defining MCP endpoints in a Phoenix router.

```elixir
# lib/hermes/server/phoenix/router.ex
defmodule Hermes.Server.Phoenix.Router do
  @moduledoc """
  Phoenix router macros for Hermes MCP server.
  """
  
  @doc """
  Defines MCP endpoints.
  """
  defmacro mcp_endpoints(server_module) do
    quote do
      post "/", Hermes.Server.Phoenix.Controller, :handle_rpc
      get "/events", Hermes.Server.Phoenix.Controller, :handle_sse
    end
  end
end
```

#### Step 3: Create the MCP Plug

Create the `Hermes.Server.Phoenix.Plug` module that provides a plug for processing MCP requests in a Phoenix application.

```elixir
# lib/hermes/server/phoenix/plug.ex
defmodule Hermes.Server.Phoenix.Plug do
  @moduledoc """
  Phoenix plug for Hermes MCP server.
  """
  
  import Plug.Conn
  
  @doc """
  Initializes the plug.
  """
  def init(opts) do
    opts
  end
  
  @doc """
  Processes an MCP request.
  """
  def call(conn, opts) do
    # TODO: Implement request processing
    conn
  end
end
```

## Testing

### Unit Tests

Create unit tests for each module to ensure that they function correctly in isolation.

```elixir
# test/hermes/server/tool_test.exs
defmodule Hermes.Server.ToolTest do
  use ExUnit.Case, async: true
  
  # Define a test tool
  defmodule TestTool do
    use Hermes.Server.Tool
    
    @impl true
    def handle(%{"x" => x, "y" => y}, _ctx) do
      {:ok, x + y}
    end
  end
  
  test "default name is derived from module name" do
    assert TestTool.name() == "test-tool"
  end
  
  test "default description is provided" do
    assert TestTool.description() =~ "TestTool"
  end
  
  test "default parameters is an empty list" do
    assert TestTool.parameters() == []
  end
  
  test "handle function works correctly" do
    assert {:ok, 5} = TestTool.handle(%{"x" => 2, "y" => 3}, %{})
  end
end
```

### Integration Tests

Create integration tests that verify the interaction between different components.

```elixir
# test/hermes/server/integration_test.exs
defmodule Hermes.Server.IntegrationTest do
  use ExUnit.Case
  
  # Define a test server
  defmodule TestServer do
    use Hermes.Server.Implementation
    
    @impl true
    def init(_opts) do
      {:ok, %{}}
    end
    
    @impl true
    def server_capabilities(_conn, state) do
      {:ok, %{}, state}
    end
    
    @impl true
    def list_tools(_conn, _params, state) do
      {:reply, [], state}
    end
    
    # Implement other required callbacks...
  end
  
  test "server initialization" do
    # TODO: Implement integration test
    assert true
  end
end
```

## Conclusion

This implementation guide provides a step-by-step approach to implementing the server-side component architecture for Hermes MCP. By following these steps, developers can create a robust, flexible, and maintainable implementation that meets the requirements specified in the GitHub issue.

The implementation follows Elixir idioms and OTP principles, providing a solid foundation for building MCP-compliant servers with Elixir and Phoenix.
