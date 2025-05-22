# Hermes MCP Server Technical Specification

## Introduction

This document provides detailed technical specifications for the server-side component architecture of Hermes MCP. It defines the behaviors, interfaces, and implementation details for building MCP-compliant servers with Elixir and Phoenix.

## Core Behaviors

### Tool Behavior

The `Hermes.Server.Tool` behavior defines the interface for MCP tools.

```elixir
defmodule Hermes.Server.Tool do
  @moduledoc """
  Defines the behavior for MCP tools.
  
  Tools are executable components that can be called by MCP clients.
  They have a name, description, parameter schema, and handler function.
  """
  
  @doc """
  Returns the name of the tool.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns a description of the tool.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the parameter schema for the tool.
  
  The schema should be a list of parameter definitions, each with a name,
  type, description, and optional constraints.
  """
  @callback parameters() :: [map()]
  
  @doc """
  Handles a tool execution request.
  
  The params map contains the parameters passed by the client.
  The context map contains information about the request context.
  
  Returns {:ok, result} on success or {:error, reason} on failure.
  """
  @callback handle(params :: map(), context :: map()) ::
              {:ok, result :: any()} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0, parameters: 0]
  
  defmacro __using__(opts) do
    quote do
      @behaviour Hermes.Server.Tool
      
      # Default implementations for optional callbacks
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

### Resource Behavior

The `Hermes.Server.Resource` behavior defines the interface for MCP resources.

```elixir
defmodule Hermes.Server.Resource do
  @moduledoc """
  Defines the behavior for MCP resources.
  
  Resources are data sources that can be accessed by MCP clients.
  They have a URI, name, description, MIME type, and read function.
  """
  
  @doc """
  Returns the URI of the resource.
  """
  @callback uri() :: String.t()
  
  @doc """
  Returns the name of the resource.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns a description of the resource.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the MIME type of the resource.
  """
  @callback mime_type() :: String.t()
  
  @doc """
  Reads the resource content.
  
  The params map contains optional parameters for reading the resource.
  The context map contains information about the request context.
  
  Returns {:ok, content} on success or {:error, reason} on failure.
  """
  @callback read(params :: map(), context :: map()) ::
              {:ok, content :: binary() | String.t()} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0]
  
  defmacro __using__(opts) do
    quote do
      @behaviour Hermes.Server.Resource
      
      # Default implementations for optional callbacks
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

### Prompt Behavior

The `Hermes.Server.Prompt` behavior defines the interface for MCP prompts.

```elixir
defmodule Hermes.Server.Prompt do
  @moduledoc """
  Defines the behavior for MCP prompts.
  
  Prompts are templates that can be used by MCP clients.
  They have a name, description, argument schema, and get function.
  """
  
  @doc """
  Returns the name of the prompt.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns a description of the prompt.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the argument schema for the prompt.
  
  The schema should be a list of argument definitions, each with a name,
  description, and optional constraints.
  """
  @callback arguments() :: [map()]
  
  @doc """
  Gets the prompt content.
  
  The args map contains the arguments passed by the client.
  The context map contains information about the request context.
  
  Returns {:ok, messages} on success or {:error, reason} on failure.
  """
  @callback get(args :: map(), context :: map()) ::
              {:ok, messages :: [map()]} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0, arguments: 0]
  
  defmacro __using__(opts) do
    quote do
      @behaviour Hermes.Server.Prompt
      
      # Default implementations for optional callbacks
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

### Implementation Behavior

The `Hermes.Server.Implementation` behavior defines the interface for MCP server implementations.

```elixir
defmodule Hermes.Server.Implementation do
  @moduledoc """
  Defines the behavior for MCP server implementations.
  
  This behavior is used by the server GenServer to delegate MCP requests
  to the appropriate handler functions.
  """
  
  @doc """
  Initializes the server state.
  """
  @callback init(opts :: keyword()) ::
              {:ok, state :: term()} | {:stop, reason :: term()}
  
  @doc """
  Returns the server capabilities.
  """
  @callback server_capabilities(conn :: term(), state :: term()) ::
              {:ok, capabilities :: map(), new_state :: term()}
  
  @doc """
  Handles client capabilities.
  """
  @callback handle_client_capabilities(conn :: term(), capabilities :: map(), state :: term()) ::
              {:ok, new_state :: term()}
  
  @doc """
  Lists available resources.
  """
  @callback list_resources(conn :: term(), params :: map(), state :: term()) ::
              {:reply, resources :: [map()], new_state :: term()}
  
  @doc """
  Gets a resource by ID.
  """
  @callback get_resource(conn :: term(), id :: String.t(), params :: map(), state :: term()) ::
              {:reply, resource :: map(), new_state :: term()}
  
  @doc """
  Lists available prompts.
  """
  @callback list_prompts(conn :: term(), params :: map(), state :: term()) ::
              {:reply, prompts :: [map()], new_state :: term()}
  
  @doc """
  Gets a prompt by ID.
  """
  @callback get_prompt(conn :: term(), id :: String.t(), params :: map(), state :: term()) ::
              {:reply, prompt :: map(), new_state :: term()}
  
  @doc """
  Lists available tools.
  """
  @callback list_tools(conn :: term(), params :: map(), state :: term()) ::
              {:reply, tools :: [map()], new_state :: term()}
  
  @doc """
  Executes a tool by ID.
  """
  @callback execute_tool(conn :: term(), id :: String.t(), params :: map(), state :: term()) ::
              {:reply, result :: term(), new_state :: term()}
  
  @doc """
  Authorizes a request.
  """
  @callback authorize(conn :: term(), method :: String.t(), params :: map(), state :: term()) ::
              {:ok, new_state :: term()} | {:error, error :: map(), new_state :: term()}
  
  @optional_callbacks [
    handle_client_capabilities: 3,
    authorize: 4
  ]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Hermes.Server.Implementation
      
      # Default implementations for optional callbacks
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

## Server Implementation

### Server GenServer

The `Hermes.Server` module provides the main server implementation.

```elixir
defmodule Hermes.Server do
  @moduledoc """
  Main server implementation for Hermes MCP.
  
  This module provides a GenServer that handles MCP requests and delegates
  them to the appropriate handler functions.
  """
  
  use GenServer
  require Logger
  
  alias Hermes.MCP.{Message, Error, ID}
  
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
  
  ## Options
  
  - `:name` - The name of the server (default: "Hermes MCP Server")
  - `:version` - The version of the server (default: "1.0.0")
  - `:module_prefix` - The prefix for modules to scan for components
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

### Attribute Parser

The `Hermes.Server.AttributeParser` module provides utilities for parsing module attributes.

```elixir
defmodule Hermes.Server.AttributeParser do
  @moduledoc """
  Utilities for parsing module attributes.
  
  This module provides functions for extracting MCP component definitions
  from module attributes.
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

## Transport Implementations

### STDIO Transport

```elixir
defmodule Hermes.Server.Transport.STDIO do
  @moduledoc """
  STDIO transport for Hermes MCP server.
  
  This module provides a transport implementation that uses standard input
  and output for communication.
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
  
  ## Options
  
  - `:server_pid` - The PID of the server GenServer
  - `:input_device` - The input device (default: :stdio)
  - `:output_device` - The output device (default: :stdio)
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

### HTTP/SSE Transport

```elixir
defmodule Hermes.Server.Transport.SSE do
  @moduledoc """
  HTTP/SSE transport for Hermes MCP server.
  
  This module provides a transport implementation that uses HTTP and
  Server-Sent Events for communication.
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
  
  ## Options
  
  - `:server_pid` - The PID of the server GenServer
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

## Phoenix Integration

### MCP Controller

```elixir
defmodule Hermes.Server.Phoenix.Controller do
  @moduledoc """
  Phoenix controller for Hermes MCP server.
  
  This module provides a controller for handling MCP requests in a
  Phoenix application.
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

### MCP Router

```elixir
defmodule Hermes.Server.Phoenix.Router do
  @moduledoc """
  Phoenix router macros for Hermes MCP server.
  
  This module provides macros for defining MCP endpoints in a
  Phoenix router.
  """
  
  @doc """
  Defines MCP endpoints.
  
  ## Example
  
      scope "/api/mcp", MyAppWeb do
        pipe_through :api
        
        mcp_endpoints MyApp.MCPServer
      end
  """
  defmacro mcp_endpoints(server_module) do
    quote do
      post "/", Hermes.Server.Phoenix.Controller, :handle_rpc
      get "/events", Hermes.Server.Phoenix.Controller, :handle_sse
    end
  end
end
```

### MCP Plug

```elixir
defmodule Hermes.Server.Phoenix.Plug do
  @moduledoc """
  Phoenix plug for Hermes MCP server.
  
  This module provides a plug for processing MCP requests in a
  Phoenix application.
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

## Conclusion

This technical specification provides a detailed blueprint for implementing the server-side component architecture for Hermes MCP. It defines the behaviors, interfaces, and implementation details for building MCP-compliant servers with Elixir and Phoenix.

The implementation will follow Elixir idioms and OTP principles, providing a robust, flexible, and maintainable solution for building MCP servers.
