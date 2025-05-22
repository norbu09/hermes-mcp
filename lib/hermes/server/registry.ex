defmodule Hermes.Server.Registry do
  @moduledoc """
  Registry for MCP server components.
  
  This module provides a registry for MCP server components (tools, resources, prompts).
  It allows for dynamic registration and discovery of components at runtime.
  
  ## Usage
  
  ```elixir
  # Start the registry
  {:ok, _pid} = Hermes.Server.Registry.start_link(name: MyApp.MCPRegistry)
  
  # Register a tool
  Hermes.Server.Registry.register_tool(MyApp.MCPRegistry, MyApp.MCP.CalculatorTool)
  
  # Get all registered tools
  tools = Hermes.Server.Registry.get_tools(MyApp.MCPRegistry)
  ```
  """
  
  use GenServer
  require Logger
  
  @type t :: GenServer.server()
  
  # Registry state
  defstruct [
    :name,
    tools: [],
    resources: [],
    prompts: []
  ]
  
  @doc """
  Starts the registry GenServer.
  
  ## Options
  
  - `:name` - The name to register the registry process under (optional)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Registers a tool module with the registry.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  - `tool_module` - The tool module to register
  """
  def register_tool(registry \\ __MODULE__, tool_module) do
    GenServer.call(registry, {:register_tool, tool_module})
  end
  
  @doc """
  Registers a resource module with the registry.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  - `resource_module` - The resource module to register
  """
  def register_resource(registry \\ __MODULE__, resource_module) do
    GenServer.call(registry, {:register_resource, resource_module})
  end
  
  @doc """
  Registers a prompt module with the registry.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  - `prompt_module` - The prompt module to register
  """
  def register_prompt(registry \\ __MODULE__, prompt_module) do
    GenServer.call(registry, {:register_prompt, prompt_module})
  end
  
  @doc """
  Gets all registered tools.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  """
  def get_tools(registry \\ __MODULE__) do
    GenServer.call(registry, :get_tools)
  end
  
  @doc """
  Gets all registered resources.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  """
  def get_resources(registry \\ __MODULE__) do
    GenServer.call(registry, :get_resources)
  end
  
  @doc """
  Gets all registered prompts.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  """
  def get_prompts(registry \\ __MODULE__) do
    GenServer.call(registry, :get_prompts)
  end
  
  @doc """
  Discovers and registers components based on module attributes.
  
  This function scans all loaded modules for MCP component attributes
  and registers them with the registry.
  
  ## Parameters
  
  - `registry` - The registry process (PID or name)
  - `module_prefix` - The prefix for modules to scan (optional)
  """
  def discover_components(registry \\ __MODULE__, module_prefix \\ nil) do
    GenServer.call(registry, {:discover_components, module_prefix})
  end
  
  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      name: Keyword.get(opts, :name, __MODULE__)
    }
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:register_tool, tool_module}, _from, state) do
    if implements_behaviour?(tool_module, Hermes.Server.Tool) do
      tools = [tool_module | state.tools] |> Enum.uniq()
      {:reply, :ok, %{state | tools: tools}}
    else
      Logger.warning("Module #{inspect(tool_module)} does not implement Hermes.Server.Tool")
      {:reply, {:error, :invalid_tool}, state}
    end
  end
  
  def handle_call({:register_resource, resource_module}, _from, state) do
    if implements_behaviour?(resource_module, Hermes.Server.Resource) do
      resources = [resource_module | state.resources] |> Enum.uniq()
      {:reply, :ok, %{state | resources: resources}}
    else
      Logger.warning("Module #{inspect(resource_module)} does not implement Hermes.Server.Resource")
      {:reply, {:error, :invalid_resource}, state}
    end
  end
  
  def handle_call({:register_prompt, prompt_module}, _from, state) do
    if implements_behaviour?(prompt_module, Hermes.Server.Prompt) do
      prompts = [prompt_module | state.prompts] |> Enum.uniq()
      {:reply, :ok, %{state | prompts: prompts}}
    else
      Logger.warning("Module #{inspect(prompt_module)} does not implement Hermes.Server.Prompt")
      {:reply, {:error, :invalid_prompt}, state}
    end
  end
  
  def handle_call(:get_tools, _from, state) do
    {:reply, state.tools, state}
  end
  
  def handle_call(:get_resources, _from, state) do
    {:reply, state.resources, state}
  end
  
  def handle_call(:get_prompts, _from, state) do
    {:reply, state.prompts, state}
  end
  
  def handle_call({:discover_components, module_prefix}, _from, state) do
    # Get all modules with the specified prefix
    modules =
      :code.all_loaded()
      |> Enum.map(fn {module, _} -> module end)
      |> filter_by_prefix(module_prefix)
    
    # Discover components using both behavior and attribute-based approaches
    # First, find modules implementing behaviors
    behavior_tools =
      modules
      |> Enum.filter(fn module ->
        implements_behaviour?(module, Hermes.Server.Tool)
      end)
    
    # Discover resources using behaviors
    behavior_resources =
      modules
      |> Enum.filter(fn module ->
        implements_behaviour?(module, Hermes.Server.Resource)
      end)
    
    # Discover prompts using behaviors
    behavior_prompts =
      modules
      |> Enum.filter(fn module ->
        implements_behaviour?(module, Hermes.Server.Prompt)
      end)
    
    # Now discover components using attribute-based approach
    {attribute_tools, attribute_resources, attribute_prompts} =
      modules
      |> Enum.reduce({[], [], []}, fn module, {tools_acc, resources_acc, prompts_acc} ->
        # Extract metadata using the attribute parser
        metadata = Hermes.Server.AttributeParser.extract_metadata(module)
        
        # Add components to the appropriate accumulator
        tools_acc = if metadata.tool, do: [module | tools_acc], else: tools_acc
        resources_acc = if metadata.resource, do: [module | resources_acc], else: resources_acc
        prompts_acc = if metadata.prompt, do: [module | prompts_acc], else: prompts_acc
        
        {tools_acc, resources_acc, prompts_acc}
      end)
    
    # Combine components from both approaches
    all_tools = (behavior_tools ++ attribute_tools) |> Enum.uniq()
    all_resources = (behavior_resources ++ attribute_resources) |> Enum.uniq()
    all_prompts = (behavior_prompts ++ attribute_prompts) |> Enum.uniq()
    
    # Update state with discovered components
    new_state = %{
      state |
      tools: (state.tools ++ all_tools) |> Enum.uniq(),
      resources: (state.resources ++ all_resources) |> Enum.uniq(),
      prompts: (state.prompts ++ all_prompts) |> Enum.uniq()
    }
    
    # Return the discovered components along with the updated state
    result = %{tools: all_tools, resources: all_resources, prompts: all_prompts}
    {:reply, {:ok, result}, new_state}
  end
  
  # Filter modules by prefix
  defp filter_by_prefix(modules, nil), do: modules
  defp filter_by_prefix(modules, prefix) do
    prefix_str = to_string(prefix)
    
    Enum.filter(modules, fn module ->
      module_str = to_string(module)
      String.starts_with?(module_str, prefix_str)
    end)
  end
  
  # Check if a module implements a behaviour
  defp implements_behaviour?(module, behaviour) do
    # Get the behaviours implemented by the module
    behaviours =
      case Code.ensure_loaded(module) do
        {:module, _} ->
          case module.module_info(:attributes) do
            attributes when is_list(attributes) ->
              Keyword.get(attributes, :behaviour, []) ++
              Keyword.get(attributes, :behavior, [])
            _ -> []
          end
        _ -> []
      end
    
    # Check if the module implements the specified behaviour
    Enum.member?(behaviours, behaviour)
  end
end
