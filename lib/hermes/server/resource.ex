defmodule Hermes.Server.Resource do
  @moduledoc """
  Defines the behavior for MCP resources.
  
  Resources are data sources that can be accessed by MCP clients.
  They have a URI, name, description, MIME type, and read function.
  
  ## Examples
  
  ```elixir
  defmodule MyApp.MCP.ReadmeResource do
    use Hermes.Server.Resource
    
    @impl true
    def uri, do: "docs://readme"
    
    @impl true
    def name, do: "Project README"
    
    @impl true
    def description, do: "The project's README file"
    
    @impl true
    def mime_type, do: "text/markdown"
    
    @impl true
    def read(_params, _ctx) do
      case File.read("README.md") do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "Failed to read README: \#{reason}"}
      end
    end
  end
  ```
  """
  
  @doc """
  Returns the URI of the resource.
  
  This URI is used to identify the resource in MCP requests.
  It should follow a scheme-like format, e.g., "docs://readme".
  """
  @callback uri() :: String.t()
  
  @doc """
  Returns the name of the resource.
  
  This name is used to provide a human-readable identifier for the resource.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns a description of the resource.
  
  This description is used to provide information about the resource to MCP clients.
  It should be a concise explanation of what the resource contains.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the MIME type of the resource.
  
  This MIME type is used to indicate the format of the resource content.
  Common values include "text/plain", "text/markdown", "application/json", etc.
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
  
  defmacro __using__(_opts) do
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
