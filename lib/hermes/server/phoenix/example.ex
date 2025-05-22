defmodule Hermes.Server.Phoenix.Example do
  @moduledoc """
  Example Phoenix application that uses the Hermes MCP server.
  
  This module provides an example of how to integrate the Hermes MCP server
  with a Phoenix application. It includes examples of defining tools, resources,
  and prompts, as well as setting up the Phoenix router and controller.
  
  ## Example Application
  
  ```elixir
  # In your application.ex
  def start(_type, _args) do
    children = [
      # Start the Endpoint
      MyAppWeb.Endpoint,
      
      # Start the MCP Server
      {Hermes.Server,
        name: MyApp.MCPServer,
        server_name: "My MCP Server",
        version: "1.0.0",
        module_prefix: MyApp.MCP
      }
    ]
    
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```
  
  ## Example Controller
  
  ```elixir
  # lib/my_app_web/controllers/mcp_controller.ex
  defmodule MyAppWeb.MCPController do
    use Hermes.Server.Phoenix.Controller, server: MyApp.MCPServer
  end
  ```
  
  ## Example Router
  
  ```elixir
  # lib/my_app_web/router.ex
  defmodule MyAppWeb.Router do
    use Phoenix.Router
    import Hermes.Server.Phoenix.Router
    
    pipeline :api do
      plug :accepts, ["json"]
      # Optional: Add authentication
      plug Hermes.Server.Phoenix.Plug.Authentication, 
        auth_fn: &MyApp.Auth.authenticate/1
    end
    
    scope "/api" do
      pipe_through :api
      
      # Define MCP endpoints
      mcp_endpoints "/mcp", MyAppWeb.MCPController
    end
  end
  ```
  
  ## Example Tool
  
  ```elixir
  # lib/my_app/mcp/calculator_tool.ex
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
    
    # Example of a streaming handler
    @impl true
    def handle_stream(%{"operation" => "long_calculation"} = params, context, progress_callback) do
      # Start the long-running operation
      progress_callback.(%{"status" => "started", "progress" => 0})
      
      # Simulate work with progress updates
      Enum.each(1..10, fn i ->
        # Do some work...
        :timer.sleep(1000)
        
        # Send a progress update
        progress_callback.(%{"status" => "in_progress", "progress" => i * 10})
      end)
      
      # Return the final result
      {:ok, %{"result" => "Long calculation completed"}}
    end
    
    # Fall back to regular handler for other operations
    def handle_stream(params, context, _progress_callback) do
      handle(params, context)
    end
  end
  ```
  
  ## Example Resource
  
  ```elixir
  # lib/my_app/mcp/example_resource.ex
  defmodule MyApp.MCP.ExampleResource do
    use Hermes.Server.Resource
    
    @impl true
    def uri, do: "example-resource"
    
    @impl true
    def name, do: "Example Resource"
    
    @impl true
    def description, do: "An example resource for demonstration"
    
    @impl true
    def mime_type, do: "text/plain"
    
    @impl true
    def read(_params, _ctx) do
      {:ok, "This is an example resource content."}
    end
  end
  ```
  
  ## Example Prompt
  
  ```elixir
  # lib/my_app/mcp/example_prompt.ex
  defmodule MyApp.MCP.ExamplePrompt do
    use Hermes.Server.Prompt
    
    @impl true
    def name, do: "example-prompt"
    
    @impl true
    def description, do: "An example prompt for demonstration"
    
    @impl true
    def arguments do
      [
        %{
          name: "name",
          type: "string",
          description: "Name to greet",
          required: true
        }
      ]
    end
    
    @impl true
    def get(%{"name" => name}, _ctx) do
      messages = [
        %{
          "role" => "system",
          "content" => "You are a helpful assistant."
        },
        %{
          "role" => "user",
          "content" => "Hello, my name is \#{name}."
        }
      ]
      
      {:ok, messages}
    end
  end
  ```
  
  ## Authentication Example
  
  ```elixir
  # lib/my_app/auth.ex
  defmodule MyApp.Auth do
    def authenticate(conn) do
      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer " <> token] ->
          # Validate the token
          if valid_token?(token) do
            {:ok, conn}
          else
            {:error, "Invalid token"}
          end
        
        _ ->
          {:error, "Missing authorization header"}
      end
    end
    
    defp valid_token?(token) do
      # Implement your token validation logic here
      token == "valid-token"
    end
  end
  ```
  """
end
