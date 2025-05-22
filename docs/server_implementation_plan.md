# Hermes MCP Server Implementation Plan

## Overview

This document outlines the implementation plan for the server-side component architecture for Hermes MCP, as requested in [GitHub Issue #17](https://github.com/cloudwalk/hermes-mcp/issues/17). The implementation will provide a comprehensive framework for building MCP-compliant servers with Elixir and Phoenix, leveraging Elixir's strengths in concurrency, fault tolerance, and pattern matching.

## Core Philosophy

Our implementation will follow these guiding principles:

1. **Elixir Idioms**: Use native Elixir constructs (behaviours, callbacks, module attributes) rather than complex DSLs
2. **Flexibility**: Support both attribute-based and explicit callback-based approaches
3. **Composability**: Allow components (tools, resources, prompts) to be defined in separate modules
4. **OTP Compliance**: Follow OTP principles for robust, fault-tolerant operation
5. **Phoenix Integration**: Seamless integration with Phoenix for HTTP endpoints

## Architecture

The server implementation will consist of the following components:

### 1. Core Behaviours

Define behaviours for the main MCP components:

- `Hermes.Server.Tool` - For defining tools that can be called by clients
- `Hermes.Server.Resource` - For defining resources that can be accessed by clients
- `Hermes.Server.Prompt` - For defining prompt templates

### 2. Server Implementation

A GenServer-based implementation that handles:

- Connection lifecycle (initialization, operation, termination)
- Message processing (JSON-RPC)
- Component registration and discovery
- State management

### 3. Transport Layers

Support for multiple transport protocols:

- STDIO for local process communication
- HTTP/SSE for web-based communication
- Streamable HTTP for the latest MCP specification

### 4. Phoenix Integration

Plug and controller components for integrating with Phoenix applications:

- Router macros for defining MCP endpoints
- Plugs for handling authentication and request processing

## Implementation Approaches

We will support two main approaches to defining MCP servers:

### Attribute-Based Approach

```elixir
defmodule MyApp.MCP.CalculatorTool do
  @behaviour Hermes.Server.Tool

  @doc """
  Perform basic arithmetic operations.
  
  @mcp_tool calculate
  @mcp_param operation String [required: true, enum: ["add", "subtract", "multiply", "divide"]]
  @mcp_param x Number [required: true]
  @mcp_param y Number [required: true]
  """
  @impl true
  def handle(%{"operation" => "add", "x" => x, "y" => y}, _ctx) do
    {:ok, x + y}
  end

  def handle(%{"operation" => "divide", "x" => _, "y" => 0}, _ctx) do
    {:error, "Cannot divide by zero"}
  end
end
```

### Callback-Based Approach

```elixir
defmodule MyApp.MCP.CalculatorTool do
  @behaviour Hermes.Server.Tool

  @impl true
  def name, do: "calculate"

  @impl true
  def description, do: "Perform basic arithmetic operations"

  @impl true
  def parameters do
    [
      %{
        name: "operation",
        type: "string",
        description: "Operation to perform",
        required: true,
        enum: ["add", "subtract", "multiply", "divide"]
      },
      %{
        name: "x",
        type: "number",
        description: "First number",
        required: true
      },
      %{
        name: "y",
        type: "number",
        description: "Second number",
        required: true
      }
    ]
  end

  @impl true
  def handle(%{"operation" => "add", "x" => x, "y" => y}, _ctx), do: {:ok, x + y}
  def handle(%{"operation" => "divide", "x" => _, "y" => 0}, _ctx), do: {:error, "Cannot divide by zero"}
end
```

## Implementation Plan

### Phase 1: Core Server Implementation ✅

1. ✅ Define core behaviours (`Tool`, `Resource`, `Prompt`)
2. ✅ Implement attribute parsing for metadata extraction
3. ✅ Create server GenServer with supervision
4. ✅ Implement basic message handling

### Phase 2: Transport Layers ✅

1. ✅ Implement STDIO transport
2. ✅ Implement HTTP/SSE transport
3. ✅ Implement Streamable HTTP transport

### Phase 3: Phoenix Integration ✅

1. ✅ Create Phoenix controller for HTTP endpoints
2. ✅ Implement router macros for MCP endpoints
3. ✅ Create authentication plugs

### Phase 4: Component Discovery and Registration ✅

1. ✅ Implement module discovery based on module attributes
2. ✅ Create registry for component registration
3. ✅ Implement dynamic component loading

### Phase 5: Testing and Documentation

1. Create comprehensive test suite
2. Write detailed documentation
3. Create example implementations

## Module Structure

```
lib/hermes/server/
├── server.ex                # Main server module
├── supervisor.ex            # Supervision tree
├── tool.ex                  # Tool behaviour
├── resource.ex              # Resource behaviour
├── prompt.ex                # Prompt behaviour
├── implementation.ex        # Implementation behaviour
├── registry.ex              # Component registry
├── transport/               # Transport implementations
│   ├── stdio.ex             # STDIO transport
│   ├── sse.ex               # SSE transport
│   └── streamable_http.ex   # Streamable HTTP transport
└── phoenix/                 # Phoenix integration
    ├── controller.ex        # MCP controller
    ├── router.ex            # Router macros
    └── plug.ex              # MCP plugs
```

## API Examples

### Server Definition

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "My MCP Server",
    version: "1.0.0",
    module_prefix: MyApp.MCP
end
```

### Phoenix Integration

```elixir
defmodule MyAppWeb.Router do
  use Phoenix.Router
  import Hermes.Server.Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/mcp", MyAppWeb do
    pipe_through :api

    mcp_endpoints MyApp.MCPServer
  end
end
```

## Conclusion

This implementation plan provides a roadmap for developing a comprehensive server-side component architecture for Hermes MCP. By leveraging Elixir's strengths and following OTP principles, we can create a robust, flexible, and maintainable implementation that meets the requirements specified in the GitHub issue.

The implementation will support both attribute-based and callback-based approaches, allowing developers to choose the style that best fits their needs. It will also integrate seamlessly with Phoenix, making it easy to build web-based MCP servers.
