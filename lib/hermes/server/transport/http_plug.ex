defmodule Hermes.Server.Transport.HTTP.Plug do
  @moduledoc """
  Plug for handling HTTP requests.
  
  This plug handles JSON-RPC requests over HTTP and forwards them to the
  HTTP transport for processing.
  """
  
  # We don't use Plug.Conn functions directly in this module,
  # but it's a common pattern in Plug modules to import it
  
  @behaviour Plug
  
  @impl Plug
  def init(opts) do
    transport = Keyword.fetch!(opts, :transport)
    %{transport: transport}
  end
  
  @impl Plug
  def call(conn, %{transport: transport}) do
    # Handle the request
    case Hermes.Server.Transport.HTTP.handle_request(transport, conn) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end
end
