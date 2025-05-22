defmodule Hermes.Examples.MCPExamples do
  @moduledoc """
  Comprehensive examples for using the Hermes MCP server.
  
  This module provides examples for:
  
  1. Setting up a Hermes MCP server
  2. Integrating with Phoenix
  3. Defining MCP components (tools, resources, prompts)
  4. Using the attribute-based approach
  5. Implementing streaming tools
  
  ## Server Setup
  
  ### Basic Server
  
  ```elixir
  # Start a standalone MCP server
  {:ok, _pid} = Hermes.Server.start_link(
    name: MyApp.MCPServer,
    server_name: "My MCP Server",
    version: "1.0.0",
    module_prefix: MyApp.MCP
  )
  ```
  
  ### In Application Supervision Tree
  
  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      YourAppWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: YourApp.PubSub},
      # Start the Endpoint (http/https)
      YourAppWeb.Endpoint,
      # Start the MCP Server Supervisor
      {Hermes.Server.Supervisor, [
        servers: [
          [
            name: YourApp.MCPServer,
            server_name: "Your MCP Server",
            version: "1.0.0",
            module_prefix: YourApp.MCP
          ]
        ]
      ]}
    ]
    
    opts = [strategy: :one_for_one, name: YourApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```
  
  ## Phoenix Integration
  
  ### Controller
  
  ```elixir
  # lib/my_app_web/controllers/mcp_controller.ex
  defmodule MyAppWeb.MCPController do
    use Hermes.Server.Phoenix.Controller, server: MyApp.MCPServer
  end
  ```
  
  ### Router
  
  ```elixir
  # lib/my_app_web/router.ex
  defmodule MyAppWeb.Router do
    use Phoenix.Router
    import Hermes.Server.Phoenix.Router
    
    pipeline :api do
      plug :accepts, ["json"]
      # Optional: Add authentication
      plug Hermes.Server.Phoenix.AuthPlug, token: "your_secret_token"
    end
    
    scope "/api" do
      pipe_through :api
      
      # Define MCP endpoints
      mcp_server "/mcp", server: YourApp.MCPServer
    end
  end
  ```
  
  ## MCP Components
  
  ### Tools
  
  #### Basic Tool (Behavior-Based)
  
  ```elixir
  defmodule YourApp.MCP.CalculatorTool do
    @behaviour Hermes.Server.Tool
    
    @impl true
    def name, do: "calculator"
    
    @impl true
    def description, do: "Perform basic arithmetic operations"
    
    @impl true
    def parameters do
      [
        %{
          "name" => "operation",
          "type" => "string",
          "description" => "Operation to perform",
          "required" => true,
          "enum" => ["add", "subtract", "multiply", "divide"]
        },
        %{
          "name" => "x",
          "type" => "number",
          "description" => "First operand",
          "required" => true
        },
        %{
          "name" => "y",
          "type" => "number",
          "description" => "Second operand",
          "required" => true
        }
      ]
    end
    
    @impl true
    def handle(%{"operation" => "add", "x" => x, "y" => y}, _context) do
      {:ok, %{"result" => x + y}}
    end
    
    def handle(%{"operation" => "subtract", "x" => x, "y" => y}, _context) do
      {:ok, %{"result" => x - y}}
    end
    
    def handle(%{"operation" => "multiply", "x" => x, "y" => y}, _context) do
      {:ok, %{"result" => x * y}}
    end
    
    def handle(%{"operation" => "divide", "x" => x, "y" => y}, _context) when y != 0 do
      {:ok, %{"result" => x / y}}
    end
    
    def handle(%{"operation" => "divide", "x" => _x, "y" => 0}, _context) do
      {:error, "Division by zero"}
    end
    
    def handle(_params, _context) do
      {:error, "Invalid parameters"}
    end
  end
  ```
  
  #### Streaming Tool
  
  ```elixir
  defmodule YourApp.MCP.CounterTool do
    @behaviour Hermes.Server.Tool
    
    @impl true
    def name, do: "counter"
    
    @impl true
    def description, do: "Count from 1 to N with a delay between each number"
    
    @impl true
    def parameters do
      [
        %{
          "name" => "count",
          "type" => "integer",
          "description" => "Number to count to",
          "required" => true
        },
        %{
          "name" => "delay_ms",
          "type" => "integer",
          "description" => "Delay between numbers in milliseconds",
          "required" => false,
          "default" => 1000
        }
      ]
    end
    
    @impl true
    def handle(params, _context) do
      count = Map.get(params, "count", 10)
      
      result = Enum.reduce(1..count, [], fn i, acc ->
        [i | acc]
      end)
      |> Enum.reverse()
      
      {:ok, %{"numbers" => result}}
    end
    
    @impl true
    def handle_stream(params, _context, progress_callback) do
      count = Map.get(params, "count", 10)
      delay_ms = Map.get(params, "delay_ms", 1000)
      
      # Send an initial progress update
      progress_callback.(%{"status" => "started", "progress" => 0, "numbers" => []})
      
      # Count with progress updates
      Enum.reduce(1..count, {[], 0}, fn i, {numbers, _progress} ->
        # Calculate progress percentage
        progress = i / count * 100
        
        # Add the current number to the list
        updated_numbers = [i | numbers]
        
        # Send a progress update
        progress_callback.(%{
          "status" => "in_progress",
          "progress" => progress,
          "numbers" => Enum.reverse(updated_numbers)
        })
        
        # Delay before the next number
        Process.sleep(delay_ms)
        
        {updated_numbers, progress}
      end)
      
      # Send a final progress update
      {final_numbers, _} = Enum.reduce(1..count, {[], 0}, fn i, {numbers, _} ->
        {[i | numbers], 0}
      end)
      
      progress_callback.(%{
        "status" => "completed",
        "progress" => 100,
        "numbers" => Enum.reverse(final_numbers)
      })
      
      :ok
    end
  end
  ```
  
  ### Resources
  
  ```elixir
  defmodule YourApp.MCP.ReadmeResource do
    @behaviour Hermes.Server.Resource
    
    @impl true
    def uri, do: "docs://readme"
    
    @impl true
    def name, do: "Project README"
    
    @impl true
    def description, do: "The project's README file"
    
    @impl true
    def mime_type, do: "text/markdown"
    
    @impl true
    def read(_params, _context) do
      case File.read("README.md") do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "Failed to read README: #{reason}"}
      end
    end
  end
  ```
  
  ### Prompts
  
  ```elixir
  defmodule YourApp.MCP.GreetingPrompt do
    @behaviour Hermes.Server.Prompt
    
    @impl true
    def name, do: "greeting"
    
    @impl true
    def description, do: "A friendly greeting prompt"
    
    @impl true
    def arguments do
      [
        %{
          "name" => "name",
          "description" => "Name of the person to greet",
          "required" => false
        }
      ]
    end
    
    @impl true
    def get(params, _context) do
      name = Map.get(params, "name", "world")
      
      prompt = "You are a friendly assistant. Greet the user named #{name} in a warm and welcoming way."
      
      {:ok, %{"prompt" => prompt}}
    end
  end
  ```
  
  ## Attribute-Based Approach
  
  You can also use the attribute-based approach to define MCP components:
  
  ```elixir
  defmodule YourApp.MCP.AttributeCalculator do
    @doc \"\"\"
    Perform basic arithmetic operations.
    
    @mcp_tool calculator
    @mcp_param operation String [required: true, enum: ["add", "subtract", "multiply", "divide"]]
    @mcp_param x Number [required: true]
    @mcp_param y Number [required: true]
    \"\"\"
    def handle(%{"operation" => "add", "x" => x, "y" => y}, _ctx) do
      {:ok, %{"result" => x + y}}
    end
    
    def handle(%{"operation" => "subtract", "x" => x, "y" => y}, _ctx) do
      {:ok, %{"result" => x - y}}
    end
    
    def handle(%{"operation" => "multiply", "x" => x, "y" => y}, _ctx) do
      {:ok, %{"result" => x * y}}
    end
    
    def handle(%{"operation" => "divide", "x" => x, "y" => y}, _ctx) when y != 0 do
      {:ok, %{"result" => x / y}}
    end
    
    def handle(%{"operation" => "divide", "x" => _x, "y" => 0}, _ctx) do
      {:error, "Division by zero"}
    end
  end
  ```
  """
  
  @doc """
  Returns a list of example MCP components.
  
  This function is a placeholder to make the module compilable.
  The real value of this module is in its documentation.
  """
  def examples do
    [
      "CalculatorTool",
      "CounterTool",
      "ReadmeResource",
      "GreetingPrompt",
      "AttributeCalculator"
    ]
  end
end
