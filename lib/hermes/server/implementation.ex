defmodule Hermes.Server.Implementation do
  @moduledoc """
  Defines the behavior for MCP server implementations.
  
  This behavior is used by the server GenServer to delegate MCP requests
  to the appropriate handler functions.
  
  ## Examples
  
  ```elixir
  defmodule MyApp.MCP.Server do
    use Hermes.Server.Implementation
    
    @impl true
    def init(opts) do
      # Store the options as initial state
      state = %{
        init_option: Keyword.get(opts, :demo_init_option, "default"),
        resources: [
          %{
            "id" => "public-resource-1",
            "name" => "Example Public Resource 1",
            "description" => "A public resource that anyone can access",
            "metadata" => %{"type" => "example", "visibility" => "public"}
          }
        ],
        prompts: [
          %{
            "id" => "sample-prompt-1",
            "name" => "Example Prompt 1",
            "description" => "A sample prompt template",
            "template" => "Hello, {{name}}! Welcome to the world of MCP."
          }
        ]
      }
      
      {:ok, state}
    end
    
    @impl true
    def server_capabilities(_conn, state) do
      # Return capabilities based on MCP spec
      caps = %{
        "serverInfo" => %{
          "name" => "MyApp MCP Server",
          "version" => "0.1.0"
        },
        "resources" => %{
          "listResources" => %{ "dynamic" => true },
          "getResource" => %{ "dynamic" => true }
        },
        "prompts" => %{
          "listPrompts" => %{ "dynamic" => true },
          "getPrompt" => %{ "dynamic" => true }
        },
        "tools" => %{
          "listTools" => %{ "dynamic" => true },
          "executeTool" => %{ "dynamic" => true }
        },
        "protocol" => %{
          "version" => "2025-03-26"
        }
      }
      
      {:ok, caps, state}
    end
    
    @impl true
    def list_resources(_conn, _params, state) do
      # Just return the resources list
      {:reply, state.resources, state}
    end
    
    # Implement other required callbacks...
  end
  ```
  """
  
  alias Hermes.Server.Context
  
  @type conn_abstraction :: Context.t()
  @type error_object :: map()
  
  @doc """
  Initializes the server state.
  
  Called when the MCP connection is established.
  
  `opts` are the options passed from the server configuration.
  
  Should return `{:ok, initial_state}` or `{:stop, reason}` if initialization fails.
  """
  @callback init(opts :: keyword()) ::
              {:ok, state :: term()} | {:stop, reason :: term()}
  
  @doc """
  Defines the capabilities of this MCP server.
  
  This is called to determine what features the server supports,
  which can then be communicated to the MCP client during capability negotiation.
  
  The returned `capabilities_map` should conform to the MCP Server Capabilities structure.
  """
  @callback server_capabilities(conn :: conn_abstraction(), state :: term()) ::
              {:ok, capabilities_map :: map(), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles the client's declared capabilities.
  
  This callback is invoked after the client shares its capabilities with the server.
  The implementation can inspect `client_capabilities` and optionally adjust its
  `state` or behavior accordingly.
  """
  @callback handle_client_capabilities(
              conn :: conn_abstraction(),
              client_capabilities :: map(),
              state :: term()
            ) ::
              {:ok, new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles a request to list available resources.
  
  `params` is a map of parameters sent by the client (e.g., filters, pagination).
  Should return `{:reply, list_of_resources, new_state}` where `list_of_resources`
  is a list of maps, each representing an MCP resource descriptor.
  Or `{:error, error_object, new_state}`.
  """
  @callback list_resources(conn :: conn_abstraction(), params :: map(), state :: term()) ::
              {:reply, list_of_resources :: list(map()), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles a request to get a specific resource by its ID.
  
  `resource_id` is the identifier of the resource.
  `params` may contain additional parameters for fetching the resource.
  Should return `{:reply, resource_data, new_state}` where `resource_data` is a map
  representing the MCP resource content and metadata.
  Or `{:error, error_object, new_state}`.
  """
  @callback get_resource(
              conn :: conn_abstraction(),
              resource_id :: String.t(),
              params :: map(),
              state :: term()
            ) ::
              {:reply, resource_data :: map(), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles a request to list available prompts.
  
  `params` is a map of parameters sent by the client.
  Should return `{:reply, list_of_prompts, new_state}` where `list_of_prompts`
  is a list of maps, each representing an MCP prompt descriptor.
  Or `{:error, error_object, new_state}`.
  """
  @callback list_prompts(conn :: conn_abstraction(), params :: map(), state :: term()) ::
              {:reply, list_of_prompts :: list(map()), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles a request to get a specific prompt template by its ID.
  
  `prompt_id` is the identifier of the prompt.
  `params` may contain additional parameters.
  Should return `{:reply, prompt_data, new_state}` where `prompt_data` is a map
  representing the MCP prompt template.
  Or `{:error, error_object, new_state}`.
  """
  @callback get_prompt(
              conn :: conn_abstraction(),
              prompt_id :: String.t(),
              params :: map(),
              state :: term()
            ) ::
              {:reply, prompt_data :: map(), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles a request to list available tools.
  
  `params` is a map of parameters sent by the client.
  Should return `{:reply, list_of_tools, new_state}` where `list_of_tools`
  is a list of maps, each representing an MCP tool descriptor (including input/output schemas).
  Or `{:error, error_object, new_state}`.
  """
  @callback list_tools(conn :: conn_abstraction(), params :: map(), state :: term()) ::
              {:reply, list_of_tools :: list(map()), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles a request to execute a specific tool by its ID.
  
  `tool_id` is the identifier of the tool.
  `tool_params` is a map of parameters provided by the client for the tool execution,
  which should conform to the tool's input schema.
  Should return `{:reply, tool_result, new_state}` where `tool_result` is the output
  of the tool execution, conforming to the tool's output schema.
  Or `{:error, error_object, new_state}`.
  """
  @callback execute_tool(
              conn :: conn_abstraction(),
              tool_id :: String.t(),
              tool_params :: map(),
              state :: term()
            ) ::
              {:reply, tool_result :: map() | any(), new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Handles an asynchronous response from the client for a server-initiated request.
  
  For example, if the server made an LLM sampling request to the client, this callback
  would be invoked when the client sends back the sampling result.
  
  `request_id` is the ID of the original server-initiated request.
  `response_data` is the data sent back by the client.
  Should typically return `{:noreply, new_state}` or `{:error, error_object, new_state}`
  if the response indicates an error or is unexpected.
  """
  @callback handle_sampling_response(
              conn :: conn_abstraction(),
              request_id :: String.t() | integer(),
              response_data :: map(),
              state :: term()
            ) ::
              {:noreply, new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @doc """
  Called when the MCP connection is terminating.
  
  This callback allows the implementation to perform any necessary cleanup.
  `reason` indicates why the connection is terminating (e.g., `:normal`, `:shutdown`, an error tuple).
  `conn_details` could be the `conn_abstraction` or other relevant data about the connection being closed.
  
  The return value is ignored.
  """
  @callback terminate(reason :: any(), conn_details :: conn_abstraction() | map(), state :: term()) ::
              any()
  
  @doc """
  Authorizes a request.
  
  This callback is invoked before processing a request to determine if the client
  is authorized to perform the requested action.
  
  `method` is the MCP method being called.
  `params` is the parameters for the method call.
  
  Should return `{:ok, new_state}` if the request is authorized, or
  `{:error, error_object, new_state}` if the request is not authorized.
  """
  @callback authorize(
              conn :: conn_abstraction(),
              method :: String.t(),
              params :: map(),
              state :: term()
            ) ::
              {:ok, new_state :: term()}
              | {:error, error_object :: error_object(), new_state :: term()}
  
  @optional_callbacks [
    handle_client_capabilities: 3,
    handle_sampling_response: 4,
    terminate: 3,
    authorize: 4
  ]
  
  defmacro __using__(_opts) do
    quote do
      @behaviour Hermes.Server.Implementation
      
      # Default implementations for optional callbacks
      def handle_client_capabilities(_conn, _client_capabilities, state) do
        {:ok, state}
      end
      
      def handle_sampling_response(_conn, _request_id, _response_data, state) do
        {:noreply, state}
      end
      
      def terminate(_reason, _conn_details, _state) do
        :ok
      end
      
      def authorize(_conn, _method, _params, state) do
        # By default, allow all requests
        # Users can override this to implement custom authorization logic
        {:ok, state}
      end
      
      defoverridable [
        handle_client_capabilities: 3,
        handle_sampling_response: 4,
        terminate: 3,
        authorize: 4
      ]
    end
  end
end
