defmodule Hermes.Server.Tool do
  @moduledoc """
  Defines the behavior for MCP tools.
  
  Tools are executable components that can be called by MCP clients.
  They have a name, description, parameter schema, and handler function.
  
  ## Examples
  
  ```elixir
  defmodule MyApp.MCP.CalculatorTool do
    use Hermes.Server.Tool
    
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
    def handle(%{"operation" => "subtract", "x" => x, "y" => y}, _ctx), do: {:ok, x - y}
    def handle(%{"operation" => "multiply", "x" => x, "y" => y}, _ctx), do: {:ok, x * y}
    def handle(%{"operation" => "divide", "x" => _, "y" => 0}, _ctx), do: {:error, "Cannot divide by zero"}
    def handle(%{"operation" => "divide", "x" => x, "y" => y}, _ctx), do: {:ok, x / y}
  end
  ```
  """
  
  @doc """
  Returns the name of the tool.
  
  This name is used to identify the tool in MCP requests.
  It should be a short, descriptive string, typically in kebab-case.
  """
  @callback name() :: String.t()
  
  @doc """
  Returns a description of the tool.
  
  This description is used to provide information about the tool to MCP clients.
  It should be a concise explanation of what the tool does.
  """
  @callback description() :: String.t()
  
  @doc """
  Returns the parameter schema for the tool.
  
  The schema should be a list of parameter definitions, each with a name,
  type, description, and optional constraints (required, enum, etc.).
  
  This schema is used to validate incoming requests and to provide
  information about the tool's parameters to MCP clients.
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
  
  defmacro __using__(_opts) do
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
