defmodule Hermes.Server.Context do
  @moduledoc """
  Defines the context for MCP server requests.
  
  The context is passed to handler functions and contains information
  about the request, such as the connection details, authentication status,
  and client capabilities.
  """
  
  defstruct [
    :connection_pid,
    :client_capabilities,
    :plug_conn,
    :request_id,
    :auth_context,
    :authenticated,
    custom_data: %{}
  ]
  
  @type t :: %__MODULE__{
    connection_pid: pid() | nil,
    client_capabilities: map() | nil,
    plug_conn: map() | nil,
    request_id: String.t() | nil,
    auth_context: map() | nil,
    authenticated: boolean(),
    custom_data: map()
  }
  
  @doc """
  Creates a new context.
  
  ## Options
  
  - `:connection_pid` - The PID of the connection process
  - `:client_capabilities` - The capabilities of the client
  - `:plug_conn` - The Plug connection (for HTTP requests)
  - `:request_id` - The ID of the request
  - `:auth_context` - Authentication context
  - `:authenticated` - Whether the request is authenticated
  - `:custom_data` - Custom data to include in the context
  """
  def new(opts \\ []) do
    %__MODULE__{
      connection_pid: Keyword.get(opts, :connection_pid),
      client_capabilities: Keyword.get(opts, :client_capabilities),
      plug_conn: Keyword.get(opts, :plug_conn),
      request_id: Keyword.get(opts, :request_id),
      auth_context: Keyword.get(opts, :auth_context),
      authenticated: Keyword.get(opts, :authenticated, false),
      custom_data: Keyword.get(opts, :custom_data, %{})
    }
  end
  
  @doc """
  Puts a value in the custom data map.
  
  ## Examples
  
      iex> context = Hermes.Server.Context.new()
      iex> context = Hermes.Server.Context.put(context, :user_id, 123)
      iex> context.custom_data.user_id
      123
  """
  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{} = context, key, value) when is_atom(key) do
    custom_data = Map.put(context.custom_data, key, value)
    %{context | custom_data: custom_data}
  end
  
  @doc """
  Gets a value from the custom data map.
  
  ## Examples
  
      iex> context = Hermes.Server.Context.new(custom_data: %{user_id: 123})
      iex> Hermes.Server.Context.get(context, :user_id)
      123
      iex> Hermes.Server.Context.get(context, :not_found)
      nil
      iex> Hermes.Server.Context.get(context, :not_found, :default)
      :default
  """
  @spec get(t(), atom(), term()) :: term()
  def get(%__MODULE__{} = context, key, default \\ nil) when is_atom(key) do
    Map.get(context.custom_data, key, default)
  end
end
