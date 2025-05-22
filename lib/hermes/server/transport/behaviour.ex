defmodule Hermes.Server.Transport.Behaviour do
  @moduledoc """
  Defines the behavior that all server-side transport implementations must follow.
  
  This behavior is similar to `Hermes.Transport.Behaviour` but adapted for
  server-side needs. It defines the callbacks required for handling incoming
  connections, processing messages, and sending responses.
  """
  
  alias Hermes.MCP.Error
  
  @type t :: GenServer.server()
  @typedoc "The JSON-RPC message encoded"
  @type message :: String.t()
  @type reason :: term() | Error.t()
  @type connection_id :: String.t()
  
  @doc """
  Starts the transport GenServer.
  """
  @callback start_link(keyword()) :: GenServer.on_start()
  
  @doc """
  Sends a message to a specific client connection.
  """
  @callback send_message(t(), connection_id(), message()) :: :ok | {:error, reason()}
  
  @doc """
  Broadcasts a message to all connected clients.
  """
  @callback broadcast_message(t(), message()) :: :ok | {:error, reason()}
  
  @doc """
  Closes a specific client connection.
  """
  @callback close_connection(t(), connection_id()) :: :ok | {:error, reason()}
  
  @doc """
  Shuts down the transport.
  """
  @callback shutdown(t()) :: :ok | {:error, reason()}
end
