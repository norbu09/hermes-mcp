defmodule Hermes.Examples.HermesMCPExamples do
  @moduledoc """
  Comprehensive examples for using the Hermes MCP server.

  This module provides complete examples for:

  1. Setting up a Hermes MCP server
  2. Integrating with Phoenix
  3. Defining MCP components (tools, resources, prompts)
  4. Using the attribute-based approach
  5. Implementing streaming tools
  6. Authentication and security

  ## Server Setup

  ### Standalone Server

  ```elixir
  # Start a standalone MCP server
  {:ok, _pid} = Hermes.Server.start_link(
  name: MyApp.MCPServer,
  server_name: "My MCP Server",
  version: "1.0.0",
  module_prefix: MyApp.MCP
  )
  ```

  ### In Phoenix add to the  Supervision Tree

  ```elixir
  ```elixir
  # In your application.ex
  def start(_type, _args) do
  children = [
  ...
  # Start the Endpoint
  MyAppWeb.Endpoint,

  # Start the MCP Server directly
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

  ## Phoenix Integration

  ### Controller

  #### Basic Controller

  ```elixir
  # lib/my_app_web/controllers/mcp_controller.ex
  defmodule MyAppWeb.MCPController do
  use Hermes.Server.Phoenix.Controller, server: MyApp.MCPServer
  end
  ```

  #### Custom Controller

  ```elixir
  defmodule MyAppWeb.CustomMCPController do
  use Phoenix.Controller
  alias Hermes.Server.Transport.StreamableHTTP

  def index(conn, _params) do
  # Add custom logic before handling the MCP request
  conn = log_request(conn)

  # Use the StreamableHTTP transport to handle the request
  StreamableHTTP.call(conn, server: MyApp.MCPServer)
  end

  defp log_request(conn) do
  # Log the request
  IO.puts("MCP request received: " <> inspect(conn.body_params))
  conn
  end
  end
  ```

  ### Router

  #### Basic Router

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
    mcp_endpoints "/mcp", MyAppWeb.MCPController
  end
  ```

  #### Advanced Router with Multiple Endpoints

  ```elixir
  defmodule MyAppWeb.Router do
  use Phoenix.Router
  import Hermes.Server.Phoenix.Router

  pipeline :api do
  plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
  plug :accepts, ["json"]
  plug Hermes.Server.Phoenix.AuthPlug, token: "your_secret_token"
  end

  scope "/api" do
  pipe_through :api

  # Public MCP endpoint
  mcp_server "/public-mcp", server: YourApp.PublicMCPServer

  # Custom controller endpoint
  post "/custom-mcp", MyAppWeb.CustomMCPController, :index
  end

  scope "/api/secure" do
  pipe_through :authenticated_api

  # Authenticated MCP endpoint
  mcp_server "/mcp", server: YourApp.SecureMCPServer
  end
  end
  ```

  ### Authentication

  #### Token-Based Authentication

  ```elixir
  # In your router.ex
  pipeline :authenticated_api do
  plug :accepts, ["json"]
  plug Hermes.Server.Phoenix.AuthPlug, token: "your_secret_token"
  end
  ```

  #### Function-Based Authentication

  ```elixir
  # Define an authentication function
  defmodule MyApp.Auth do
  def authenticate(token) do
  # Check if the token is valid
  case MyApp.Accounts.verify_token(token) do
    {:ok, user_id} -> true
    _ -> false
  end
  end
  end

  # In your router.ex
  pipeline :authenticated_api do
  plug :accepts, ["json"]
  plug Hermes.Server.Phoenix.AuthPlug, validator: &MyApp.Auth.authenticate/1
  end
  ```

  ## MCP Components

  ### Tools

  #### Basic Tool (Behavior-Based)

  ```elixir
  defmodule MyApp.MCP.CalculatorTool do
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

  #### Alternative Streaming Tool Example

  ```elixir
  defmodule YourApp.MCP.LongCalculationTool do
  @behaviour Hermes.Server.Tool

  @impl true
  def name, do: "long_calculation"

  @impl true
  def description, do: "Perform a long-running calculation with progress updates"

  @impl true
  def parameters do
  [
    %{
      "name" => "iterations",
      "type" => "integer",
      "description" => "Number of iterations",
      "required" => false,
      "default" => 10
    }
  ]
  end

  @impl true
  def handle(params, _context) do
  # Non-streaming implementation
  iterations = Map.get(params, "iterations", 10)

  # Simulate a long calculation
  result = Enum.reduce(1..iterations, 0, fn i, acc ->
    Process.sleep(100)
    acc + i
  end)

  {:ok, %{"result" => result}}
  end

  @impl true
  def handle_stream(params, _context, progress_callback) do
  # Streaming implementation
  iterations = Map.get(params, "iterations", 10)

  # Start the long-running operation
  progress_callback.(%{"status" => "started", "progress" => 0})

  # Simulate work with progress updates
  result = Enum.reduce(1..iterations, 0, fn i, acc ->
    # Do some work...
    Process.sleep(500)
    
    # Calculate progress
    progress = i / iterations * 100
    
    # Send a progress update
    progress_callback.(%{
      "status" => "in_progress", 
      "progress" => progress,
      "current_value" => acc + i
    })
    
    acc + i
  end)

  # Send the final result
  progress_callback.(%{
    "status" => "completed",
    "progress" => 100,
    "result" => result
  })

  :ok
  end
  end
  ```

  ### Resources

  #### Basic Resource

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
    {:error, reason} -> {:error, "Failed to read README: " <> inspect(reason)}
  end
  end
  end
  ```

  #### Dynamic Resource

  ```elixir
  defmodule YourApp.MCP.UserDocumentResource do
  @behaviour Hermes.Server.Resource

  @impl true
  def uri, do: "docs://user-document"

  @impl true
  def name, do: "User Document"

  @impl true
  def description, do: "A document specific to the user"

    @impl true
  def mime_type, do: "text/plain"

  @impl true
  def read(params, context) do
  # Extract user ID from context
  user_id = get_in(context.custom_data, [:user_id])

  if user_id do
    # Fetch the document for the user
    case YourApp.Documents.get_document(user_id, params["document_id"]) do
      {:ok, document} -> {:ok, document.content}
      {:error, reason} -> {:error, "Failed to fetch document: " <> inspect(reason)}
    end
  else
    {:error, "User not authenticated"}
  end
  end
  end
  ```

  ### Prompts

  #### Basic Prompt

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

  prompt = "You are a friendly assistant. Greet the user named " <> name <> " in a warm and welcoming way."

  {:ok, %{"prompt" => prompt}}
  end
  end
  ```

  #### Chat Prompt

  ```elixir
  defmodule YourApp.MCP.ChatPrompt do
  @behaviour Hermes.Server.Prompt

  @impl true
  def name, do: "chat"

  @impl true
  def description, do: "A chat prompt with system and user messages"

  @impl true
  def arguments do
  [
    %{
      "name" => "name",
      "description" => "Name of the user",
      "required" => false
    },
    %{
      "name" => "query",
      "description" => "User's query",
      "required" => true
    }
  ]
  end

  @impl true
  def get(%{"name" => name, "query" => query}, _context) do
  messages = [
    %{
      "role" => "system",
      "content" => "You are a helpful assistant."
    },
    %{
      "role" => "user",
      "content" => "Hello, my name is " <> name <> ". " <> query
    }
  ]

  {:ok, %{"messages" => messages}}
  end

  def get(%{"query" => query}, context) do
  # Use default name or extract from context
  name = get_in(context.custom_data, [:user_name]) || "User"

  get(%{"name" => name, "query" => query}, context)
  end
  end
  ```

  ## Attribute-Based Approach

  You can also use the attribute-based approach to define MCP components:

  ### Attribute-Based Tool

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

  ### Attribute-Based Resource

  defmodule YourApp.MCP.AttributeResource do
  @doc \"""
  A simple text resource.

  @mcp_resource text://example
  @mcp_mime_type text/plain
  """
  def read(_params, _context) do
    {:ok, "This is an example resource defined using attributes."}
  end
end

### Attribute-Based Prompt

defmodule YourApp.MCP.AttributePrompt do
  @moduledoc false
  @doc """
  A simple greeting prompt.

  @mcp_prompt simple_greeting
  @mcp_arg name [required: false, description: "Name to greet"]
  """
  def get(params, _context) do
    name = Map.get(params, "name", "world")

    {:ok,
     %{
       "prompt" => "Hello, " <> name <> "! How can I help you today?"
     }}
  end
end

## Complete Application Example

# Here is a complete example of a Phoenix application that uses the Hermes MCP server:

# lib/my_app/application.ex
defmodule MyApp.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Start the Endpoint
      MyAppWeb.Endpoint,

      # Start the MCP Server
      {Hermes.Server.Supervisor,
       [
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

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# TODO: this needs fixing
# lib/my_app_web/router.ex
# defmodule MyAppWeb.Router do
#   use Phoenix.Router
#
#   import Hermes.Server.Phoenix.Router
#
#   pipeline :api do
#     plug(:accepts, ["json"])
#     plug(Hermes.Server.Phoenix.AuthPlug, token: System.get_env("MCP_API_KEY"))
#   end
#
#   scope "/api" do
#     pipe_through(:api)
#
#     mcp_server("/mcp", server: MyApp.MCPServer)
#   end
# end

# lib/my_app/mcp/calculator_tool.ex
defmodule MyApp.MCP.CalculatorTool do
  @moduledoc false
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

  # Other operations...
end

# lib/my_app/mcp/readme_resource.ex
defmodule MyApp.MCP.ReadmeResource do
  @moduledoc false
  @behaviour Hermes.Server.Resource

  @impl true
  def uri, do: "docs://readme"

  @impl true
  def name, do: "README"

  @impl true
  def description, do: "Project README"

  @impl true
  def mime_type, do: "text/markdown"

  @impl true
  def read(_params, _context) do
    case File.read("README.md") do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Failed to read README: \#{reason}"}
    end
  end
end

# lib/my_app/mcp/greeting_prompt.ex
defmodule MyApp.MCP.GreetingPrompt do
  @moduledoc false
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

    prompt = "You are a friendly assistant. Greet the user named \#{name} in a warm and welcoming way."

    {:ok, %{"prompt" => prompt}}
  end

  """

  @doc \"""
  Returns a list of example MCP components.

  This function is a placeholder to make the module compilable.
  The real value of this module is in its documentation.
  """

  def examples do
    [
      "CalculatorTool",
      "CounterTool",
      "LongCalculationTool",
      "ReadmeResource",
      "UserDocumentResource",
      "GreetingPrompt",
      "ChatPrompt",
      "AttributeCalculator",
      "AttributeResource",
      "AttributePrompt"
    ]
  end
end
