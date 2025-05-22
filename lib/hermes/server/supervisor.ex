defmodule Hermes.Server.Supervisor do
  @moduledoc """
  Supervisor for Hermes MCP server processes.
  
  This module provides a supervisor that manages the lifecycle of MCP server
  processes and their associated transports.
  
  ## Usage
  
  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # Start the MCP Server Supervisor
      {Hermes.Server.Supervisor, [
        servers: [
          [
            name: MyApp.MCPServer,
            server_name: "My MCP Server",
            version: "1.0.0",
            module_prefix: MyApp.MCP
          ]
        ]
      ]}
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
  ```
  """
  
  use Supervisor
  require Logger
  
  @doc """
  Starts the supervisor.
  
  ## Options
  
  - `:servers` - A list of server configurations, each a keyword list of options
    to pass to `Hermes.Server.start_link/1`
  """
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl Supervisor
  def init(opts) do
    servers = Keyword.get(opts, :servers, [])
    
    # Create child specs for each server
    children =
      servers
      |> Enum.map(fn server_opts ->
        {Hermes.Server, server_opts}
      end)
    
    # Start the supervisor
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Starts a new MCP server.
  
  ## Options
  
  - `:name` - The name to register the server process under (required)
  - `:server_name` - The human-readable name of the server (default: "Hermes MCP Server")
  - `:version` - The version of the server (default: "1.0.0")
  - `:module_prefix` - The prefix for modules to scan for components
  - `:tools` - A list of modules implementing the `Hermes.Server.Tool` behavior
  - `:resources` - A list of modules implementing the `Hermes.Server.Resource` behavior
  - `:prompts` - A list of modules implementing the `Hermes.Server.Prompt` behavior
  - `:handler_module` - A module implementing the `Hermes.Server.Implementation` behavior
  
  ## Returns
  
  - `{:ok, pid}` - The server was started successfully
  - `{:error, reason}` - The server failed to start
  """
  def start_server(opts) do
    _name = Keyword.fetch!(opts, :name)
    
    # Create a child spec for the server
    child_spec = {Hermes.Server, opts}
    
    # Start the server
    Supervisor.start_child(__MODULE__, child_spec)
  end
  
  @doc """
  Stops an MCP server.
  
  ## Parameters
  
  - `name` - The name of the server to stop
  
  ## Returns
  
  - `:ok` - The server was stopped successfully
  - `{:error, reason}` - The server failed to stop
  """
  def stop_server(name) do
    # Find the child spec for the server
    case Supervisor.which_children(__MODULE__)
         |> Enum.find(fn {_, pid, _, _} -> 
           Process.info(pid, :registered_name) == {:registered_name, name}
         end) do
      {id, _, _, _} ->
        # Stop the server
        Supervisor.terminate_child(__MODULE__, id)
        Supervisor.delete_child(__MODULE__, id)
        :ok
      nil ->
        {:error, :not_found}
    end
  end
end
