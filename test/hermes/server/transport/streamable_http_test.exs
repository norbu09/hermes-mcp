defmodule Hermes.Server.Transport.StreamableHTTPTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Hermes.Server.Transport.StreamableHTTP

  setup do
    # Start a server for testing
    server_name = :"#{__MODULE__}.Server.#{System.unique_integer([:positive])}"
    
    {:ok, _pid} = Hermes.Server.start_link(
      name: server_name,
      server_name: "Test MCP Server",
      version: "1.0.0"
    )
    
    %{server: server_name}
  end

  describe "init/1" do
    test "initializes transport options" do
      opts = StreamableHTTP.init(server: :test_server)
      assert opts[:server] == :test_server
    end
  end

  describe "call/2" do
    test "handles standard JSON-RPC requests", %{server: server} do
      # Create a test conn with a JSON-RPC request
      conn = conn(:post, "/", %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "params" => %{
          "capabilities" => %{}
        },
        "id" => "1"
      })
      |> put_req_header("content-type", "application/json")
      
      # Call the transport
      conn = StreamableHTTP.call(conn, server: server)
      
      # Assert the response
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
      
      response = Jason.decode!(conn.resp_body)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "1"
      assert response["result"]["name"] == "Test MCP Server"
      assert response["result"]["version"] == "1.0.0"
    end

    test "handles streaming requests with ndjson content type", %{server: server} do
      # Create a test conn with a streaming request
      conn = conn(:post, "/", %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "params" => %{
          "capabilities" => %{
            "streaming" => true
          }
        },
        "id" => "1"
      })
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/x-ndjson")
      
      # Call the transport
      conn = StreamableHTTP.call(conn, server: server)
      
      # Assert the response
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/x-ndjson; charset=utf-8"]
      
      # The response should be a valid NDJSON line
      [line] = String.split(conn.resp_body, "\n", trim: true)
      response = Jason.decode!(line)
      
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "1"
      assert response["result"]["name"] == "Test MCP Server"
      assert response["result"]["version"] == "1.0.0"
    end

    test "returns 400 for invalid JSON", %{server: server} do
      # Create a test conn with invalid JSON
      conn = conn(:post, "/", "{invalid json")
      |> put_req_header("content-type", "application/json")
      
      # Call the transport
      conn = StreamableHTTP.call(conn, server: server)
      
      # Assert the response
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32700
    end

    test "returns 415 for unsupported content type", %{server: server} do
      # Create a test conn with unsupported content type
      conn = conn(:post, "/", "some data")
      |> put_req_header("content-type", "text/plain")
      
      # Call the transport
      conn = StreamableHTTP.call(conn, server: server)
      
      # Assert the response
      assert conn.status == 415
    end

    test "handles streaming tool execution", %{server: server} do
      # Mock a streaming tool execution
      # This is a simplified test that just verifies the transport sets up streaming correctly
      
      # Create a test conn with a streaming tool execution request
      conn = conn(:post, "/", %{
        "jsonrpc" => "2.0",
        "method" => "execute_tool",
        "params" => %{
          "tool_id" => "test_tool",
          "params" => %{}
        },
        "id" => "1"
      })
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/x-ndjson")
      
      # We can't fully test the streaming behavior here, but we can verify
      # that the transport sets the proper headers and connection state
      conn = StreamableHTTP.call(conn, server: server)
      
      # Assert the response headers for streaming
      assert get_resp_header(conn, "content-type") == ["application/x-ndjson; charset=utf-8"]
      assert get_resp_header(conn, "transfer-encoding") == ["chunked"]
    end
  end
end
