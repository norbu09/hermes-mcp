defmodule Hermes.Server do
  @moduledoc """
  Main server implementation for Hermes MCP.

  This module provides a GenServer that handles MCP requests and delegates
  them to the appropriate handler functions. It supports both attribute-based
  and callback-based approaches to defining MCP components.

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
      }
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
  ```

  ## Options

  - `:name` - The name to register the server process under (required)
  - `:server_name` - The human-readable name of the server (default: "Hermes MCP Server")
  - `:version` - The version of the server (default: "1.0.0")
  - `:module_prefix` - The prefix for modules to scan for components
  - `:tools` - A list of modules implementing the `Hermes.Server.Tool` behavior
  - `:resources` - A list of modules implementing the `Hermes.Server.Resource` behavior
  - `:prompts` - A list of modules implementing the `Hermes.Server.Prompt` behavior
  - `:handler_module` - A module implementing the `Hermes.Server.Implementation` behavior
  """

  use GenServer
  require Logger

  alias Hermes.Server.Context

  # Server state
  defstruct [
    :name,
    :server_name,
    :version,
    :module_prefix,
    :tools,
    :resources,
    :prompts,
    :handler_module,
    :handler_state,
    :initialized,
    :client_capabilities
  ]

  @doc """
  Starts the server GenServer.

  ## Options

  - `:name` - The name to register the server process under (required)
  - `:server_name` - The human-readable name of the server (default: "Hermes MCP Server")
  - `:version` - The version of the server (default: "1.0.0")
  - `:module_prefix` - The prefix for modules to scan for components
  - `:tools` - A list of modules implementing the `Hermes.Server.Tool` behavior
  - `:resources` - A list of modules implementing the `Hermes.Server.Resource` behavior
  - `:prompts` - A list of modules implementing the `Hermes.Server.Prompt` behavior
  - `:handler_module` - A module implementing the `Hermes.Server.Implementation` behavior
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    server_name = Keyword.get(opts, :server_name, "Hermes MCP Server")
    version = Keyword.get(opts, :version, "1.0.0")
    module_prefix = Keyword.get(opts, :module_prefix)
    tools = Keyword.get(opts, :tools, [])
    resources = Keyword.get(opts, :resources, [])
    prompts = Keyword.get(opts, :prompts, [])
    handler_module = Keyword.get(opts, :handler_module)

    # Initialize state
    state = %__MODULE__{
      name: Keyword.get(opts, :name),
      server_name: server_name,
      version: version,
      module_prefix: module_prefix,
      tools: [],
      resources: [],
      prompts: [],
      handler_module: handler_module,
      initialized: false,
      client_capabilities: nil
    }

    # Discover components if module_prefix is provided
    state =
      if module_prefix do
        discover_components(state)
      else
        state
      end

    # Add explicitly provided components
    state = add_components(state, :tools, tools)
    state = add_components(state, :resources, resources)
    state = add_components(state, :prompts, prompts)

    # Initialize handler if provided
    state =
      if handler_module do
        case handler_module.init(opts) do
          {:ok, handler_state} ->
            %{state | handler_state: handler_state}

          {:stop, reason} ->
            Logger.error("Failed to initialize handler module: #{inspect(reason)}")
            state
        end
      else
        state
      end

    {:ok, state}
  end

  @doc """
  Processes an MCP request.

  This function is called by transport implementations to process
  incoming MCP requests.

  ## Parameters

  - `server` - The server process (PID or name)
  - `request` - The MCP request map
  - `context` - The request context

  ## Returns

  - `{:ok, response}` - The MCP response
  - `{:error, error}` - An error occurred
  """
  def process_request(server, request, context \\ %{}) do
    GenServer.call(server, {:process_request, request, context})
  end

  @impl GenServer
  def handle_call({:process_request, request, context}, _from, state) do
    # Create a proper context struct if not already one
    context =
      if is_map(context) and not is_struct(context) do
        Context.new(
          connection_pid: self(),
          client_capabilities: state.client_capabilities,
          request_id: request["id"]
        )
      else
        context
      end

    # Process the request
    case process_mcp_request(request, context, state) do
      {:reply, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, error, new_state} ->
        {:reply, {:error, error}, new_state}
    end
  end

  # Process an MCP request
  defp process_mcp_request(%{"method" => method} = request, context, state) do
    params = Map.get(request, "params", %{})

    # Check if the server is initialized
    if method != "initialize" and method != "mcp/initialize" and not state.initialized do
      {:error, %{code: -32002, message: "Server not initialized"}, state}
    else
      # Process the request based on the method
      case method do
        "initialize" ->
          handle_initialize(params, context, state)

        "mcp/initialize" ->
          handle_initialize(params, context, state)

        "resources/list" ->
          handle_list_resources(params, context, state)

        "mcp/resources/list" ->
          handle_list_resources(params, context, state)

        "resources/get" ->
          resource_id = Map.get(params, "id")
          handle_get_resource(resource_id, params, context, state)

        "mcp/resources/get" ->
          resource_id = Map.get(params, "id")
          handle_get_resource(resource_id, params, context, state)

        "prompts/list" ->
          handle_list_prompts(params, context, state)

        "mcp/prompts/list" ->
          handle_list_prompts(params, context, state)

        "prompts/get" ->
          prompt_id = Map.get(params, "id")
          handle_get_prompt(prompt_id, params, context, state)

        "mcp/prompts/get" ->
          prompt_id = Map.get(params, "id")
          handle_get_prompt(prompt_id, params, context, state)

        "tools/list" ->
          handle_list_tools(params, context, state)

        "mcp/tools/list" ->
          handle_list_tools(params, context, state)

        "tools/execute" ->
          tool_id = Map.get(params, "id")
          tool_params = Map.get(params, "params", %{})
          handle_execute_tool(tool_id, tool_params, context, state)

        "mcp/tools/execute" ->
          tool_id = Map.get(params, "id")
          tool_params = Map.get(params, "params", %{})
          handle_execute_tool(tool_id, tool_params, context, state)

        _ ->
          {:error, %{code: -32601, message: "Method not found: #{method}"}, state}
      end
    end
  end

  defp process_mcp_request(_request, _context, state) do
    {:error, %{code: -32600, message: "Invalid request"}, state}
  end

  # Handle initialize request
  defp handle_initialize(params, context, state) do
    # Extract client capabilities
    client_capabilities = Map.get(params, "capabilities", %{})

    # Update state with client capabilities
    state = %{state | client_capabilities: client_capabilities, initialized: true}

    # Notify handler of client capabilities if available
    state =
      if state.handler_module do
        case state.handler_module.handle_client_capabilities(
               context,
               client_capabilities,
               state.handler_state
             ) do
          {:ok, new_handler_state} ->
            %{state | handler_state: new_handler_state}

          {:error, _error, new_handler_state} ->
            %{state | handler_state: new_handler_state}
        end
      else
        state
      end

    # Build server capabilities
    server_capabilities =
      if state.handler_module do
        case state.handler_module.server_capabilities(context, state.handler_state) do
          {:ok, caps, new_handler_state} ->
            %{state | handler_state: new_handler_state}
            caps

          {:error, _error, new_handler_state} ->
            %{state | handler_state: new_handler_state}
            %{}
        end
      else
        %{
          "resources" => %{
            "listResources" => %{"dynamic" => true},
            "getResource" => %{"dynamic" => true}
          },
          "prompts" => %{
            "listPrompts" => %{"dynamic" => true},
            "getPrompt" => %{"dynamic" => true}
          },
          "tools" => %{
            "listTools" => %{"dynamic" => true},
            "executeTool" => %{"dynamic" => true}
          }
        }
      end

    # Build response
    response = %{
      "serverInfo" => %{
        "name" => state.server_name,
        "version" => state.version
      },
      "protocolVersion" => "2025-03-26",
      "capabilities" => server_capabilities
    }

    {:reply, response, state}
  end

  # Handle list_resources request
  defp handle_list_resources(params, context, state) do
    if state.handler_module do
      case state.handler_module.list_resources(context, params, state.handler_state) do
        {:reply, resources, new_handler_state} ->
          {:reply, %{"resources" => resources}, %{state | handler_state: new_handler_state}}

        {:error, error, new_handler_state} ->
          {:error, error, %{state | handler_state: new_handler_state}}
      end
    else
      # Default implementation
      resources =
        state.resources
        |> Enum.map(fn resource_module ->
          %{
            "id" => resource_module.uri(),
            "name" => resource_module.name(),
            "description" => resource_module.description(),
            "mimeType" => resource_module.mime_type()
          }
        end)

      {:reply, %{"resources" => resources}, state}
    end
  end

  # Handle get_resource request
  defp handle_get_resource(resource_id, params, context, state) do
    if state.handler_module do
      case state.handler_module.get_resource(context, resource_id, params, state.handler_state) do
        {:reply, resource, new_handler_state} ->
          {:reply, resource, %{state | handler_state: new_handler_state}}

        {:error, error, new_handler_state} ->
          {:error, error, %{state | handler_state: new_handler_state}}
      end
    else
      # Default implementation
      case Enum.find(state.resources, fn resource_module ->
             resource_module.uri() == resource_id
           end) do
        nil ->
          {:error, %{code: -32602, message: "Resource not found: #{resource_id}"}, state}

        resource_module ->
          case resource_module.read(params, context) do
            {:ok, content} ->
              resource = %{
                "id" => resource_module.uri(),
                "name" => resource_module.name(),
                "description" => resource_module.description(),
                "mimeType" => resource_module.mime_type(),
                "content" => content
              }

              {:reply, resource, state}

            {:error, reason} ->
              {:error, %{code: -32603, message: reason}, state}
          end
      end
    end
  end

  # Handle list_prompts request
  defp handle_list_prompts(params, context, state) do
    if state.handler_module do
      case state.handler_module.list_prompts(context, params, state.handler_state) do
        {:reply, prompts, new_handler_state} ->
          {:reply, %{"prompts" => prompts}, %{state | handler_state: new_handler_state}}

        {:error, error, new_handler_state} ->
          {:error, error, %{state | handler_state: new_handler_state}}
      end
    else
      # Default implementation
      prompts =
        state.prompts
        |> Enum.map(fn prompt_module ->
          %{
            "id" => prompt_module.name(),
            "name" => prompt_module.name(),
            "description" => prompt_module.description(),
            "arguments" => prompt_module.arguments()
          }
        end)

      {:reply, %{"prompts" => prompts}, state}
    end
  end

  # Handle get_prompt request
  defp handle_get_prompt(prompt_id, params, context, state) do
    if state.handler_module do
      case state.handler_module.get_prompt(context, prompt_id, params, state.handler_state) do
        {:reply, prompt, new_handler_state} ->
          {:reply, prompt, %{state | handler_state: new_handler_state}}

        {:error, error, new_handler_state} ->
          {:error, error, %{state | handler_state: new_handler_state}}
      end
    else
      # Default implementation
      case Enum.find(state.prompts, fn prompt_module -> prompt_module.name() == prompt_id end) do
        nil ->
          {:error, %{code: -32602, message: "Prompt not found: #{prompt_id}"}, state}

        prompt_module ->
          case prompt_module.get(params, context) do
            {:ok, prompt_data} ->
              {:reply, prompt_data, state}

            {:error, reason} ->
              {:error, %{code: -32603, message: reason}, state}
          end
      end
    end
  end

  # Handle list_tools request
  defp handle_list_tools(params, context, state) do
    if state.handler_module do
      case state.handler_module.list_tools(context, params, state.handler_state) do
        {:reply, tools, new_handler_state} ->
          {:reply, %{"tools" => tools}, %{state | handler_state: new_handler_state}}

        {:error, error, new_handler_state} ->
          {:error, error, %{state | handler_state: new_handler_state}}
      end
    else
      # Default implementation
      tools =
        state.tools
        |> Enum.map(fn tool_module ->
          %{
            "id" => tool_module.name(),
            "name" => tool_module.name(),
            "description" => tool_module.description(),
            "parameters" => tool_module.parameters()
          }
        end)

      {:reply, %{"tools" => tools}, state}
    end
  end

  # Handle execute_tool request
  defp handle_execute_tool(tool_id, tool_params, context, state) do
    # Check if this is a streaming request
    is_streaming = get_in(context.custom_data, [:streaming]) == true
    _client_id = get_in(context.custom_data, [:client_id])

    if state.handler_module do
      # Use the handler module if available
      case state.handler_module.execute_tool(context, tool_id, tool_params, state.handler_state) do
        {:reply, result, new_handler_state} ->
          {:reply, result, %{state | handler_state: new_handler_state}}

        {:stream, stream_fn, new_handler_state} when is_streaming and is_function(stream_fn) ->
          # Handle streaming response with the provided stream function
          Task.start(fn ->
            stream_fn.(fn progress ->
              # Send progress updates through the connection
              send(context.connection_pid, {:send_progress, progress})
            end)
          end)

          # Return an immediate response indicating streaming has started
          {:reply, %{"status" => "streaming"}, %{state | handler_state: new_handler_state}}

        {:error, error, new_handler_state} ->
          {:error, error, %{state | handler_state: new_handler_state}}
      end
    else
      # Default implementation
      case Enum.find(state.tools, fn tool_module -> tool_module.name() == tool_id end) do
        nil ->
          {:error, %{code: -32602, message: "Tool not found: #{tool_id}"}, state}

        tool_module ->
          if is_streaming and function_exported?(tool_module, :handle_stream, 3) do
            # Use streaming handler if available and streaming is requested
            Task.start(fn ->
              # Call the streaming handler
              tool_module.handle_stream(tool_params, context, fn progress ->
                # Send progress updates through the connection
                send(context.connection_pid, {:send_progress, progress})
              end)
            end)

            # Return an immediate response indicating streaming has started
            {:reply, %{"status" => "streaming"}, state}
          else
            # Fall back to regular handler
            case tool_module.handle(tool_params, context) do
              {:ok, result} ->
                {:reply, result, state}

              {:error, reason} ->
                {:error, %{code: -32603, message: reason}, state}
            end
          end
      end
    end
  end

  # Discover components based on module prefix
  defp discover_components(state) do
    # Start the registry if not already started
    registry_name = Module.concat(state.name, Registry)

    case Process.whereis(registry_name) do
      nil ->
        # Start the registry
        {:ok, _pid} = Hermes.Server.Registry.start_link(name: registry_name)

      _pid ->
        # Registry already started
        :ok
    end

    # First discover behavior-based components using the registry
    {:ok, %{tools: _behavior_tools, resources: _behavior_resources, prompts: _behavior_prompts}} =
      Hermes.Server.Registry.discover_components(registry_name, state.module_prefix)

    # Then register attribute-based components explicitly
    register_attribute_components(registry_name, state.module_prefix)

    # Get all components from the registry
    tools = Hermes.Server.Registry.get_tools(registry_name)
    resources = Hermes.Server.Registry.get_resources(registry_name)
    prompts = Hermes.Server.Registry.get_prompts(registry_name)

    # Update state with all components
    %{
      state
      | tools: (state.tools ++ tools) |> Enum.uniq(),
        resources: (state.resources ++ resources) |> Enum.uniq(),
        prompts: (state.prompts ++ prompts) |> Enum.uniq()
    }
  end

  # Register attribute-based components with the registry
  defp register_attribute_components(registry, module_prefix) do
    # Get all modules with the specified prefix
    modules =
      :code.all_loaded()
      |> Enum.map(fn {module, _} -> module end)
      |> Enum.filter(fn module ->
        module_str = to_string(module)
        String.starts_with?(module_str, to_string(module_prefix))
      end)

    # Register each module with attribute-based metadata
    Enum.each(modules, fn module ->
      # Extract metadata using the attribute parser
      metadata = Hermes.Server.AttributeParser.extract_metadata(module)

      # Only register if the module has any MCP-related attributes
      if metadata.tool or metadata.resource or metadata.prompt do
        Hermes.Server.Registry.register_attribute_component(registry, module, metadata)
      end
    end)
  end

  # Add components to state
  defp add_components(state, :tools, tools) do
    %{state | tools: state.tools ++ tools}
  end

  defp add_components(state, :resources, resources) do
    %{state | resources: state.resources ++ resources}
  end

  defp add_components(state, :prompts, prompts) do
    %{state | prompts: state.prompts ++ prompts}
  end
end
