defmodule Hermes.Server.Prompt do
  @moduledoc """
  Defines the behavior for MCP prompts.
  
  Prompts are templates that can be used by MCP clients.
  They have a name, description, argument schema, and get function.
  
  ## Examples
  
  ```elixir
  defmodule MyApp.MCP.GreetingPrompt do
    use Hermes.Server.Prompt
    
    @impl true
    def name, do: "greeting"
    
    @impl true
    def description, do: "A friendly greeting prompt"
    
    @impl true
    def arguments do
      [
        %{
          name: "name",
          description: "Name of the person to greet",
          required: false
        }
      ]
    end
    
    @impl true
    def get(%{"name" => name}, _ctx) when is_binary(name) do
      messages = [
        %{
          role: "assistant",
          content: %{
            type: "text",
            text: "Hello, \#{name}! How can I help you today?"
          }
        }
      ]
      
      {:ok, %{title: "A friendly greeting", messages: messages}}
    end
    
    def get(_args, _ctx) do
      messages = [
        %{
          role: "assistant",
          content: %{
            type: "text",
            text: "Hello there! How can I help you today?"
          }
        }
      ]
      
      {:ok, %{title: "A friendly greeting", messages: messages}}
    end
  end
  ```
  """
  
  @doc """
  Returns the name of the prompt.
  
  This name is used to identify the prompt in MCP requests.
  It should be a short, descriptive string, typically in kebab-case.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns a description of the prompt.
  
  This description is used to provide information about the prompt to MCP clients.
  It should be a concise explanation of what the prompt does.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the argument schema for the prompt.
  
  The schema should be a list of argument definitions, each with a name,
  description, and optional constraints (required, etc.).
  
  This schema is used to validate incoming requests and to provide
  information about the prompt's arguments to MCP clients.
  """
  @callback arguments() :: [map()]
  
  @doc """
  Gets the prompt content.
  
  The args map contains the arguments passed by the client.
  The context map contains information about the request context.
  
  Returns {:ok, %{title: String.t(), messages: [map()]}} on success
  or {:error, reason} on failure.
  """
  @callback get(args :: map(), context :: map()) ::
              {:ok, %{title: String.t(), messages: [map()]}} | {:error, reason :: String.t()}
              
  @optional_callbacks [name: 0, description: 0, arguments: 0]
  
  defmacro __using__(_opts) do
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
