defmodule Hermes.Server.Phoenix.ControllerTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Hermes.Server.Phoenix.Controller

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
    test "initializes controller options" do
      opts = Controller.init(server: :test_server)
      assert opts[:server] == :test_server
    end
  end

  describe "call/2" do
    test "handles JSON-RPC requests", %{server: server} do
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
      
      # Call the controller
      conn = Controller.call(conn, server: server)
      
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
      
      # Call the controller
      conn = Controller.call(conn, server: server)
      
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
      
      # Call the controller
      conn = Controller.call(conn, server: server)
      
      # Assert the response
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32700
    end

    test "returns 405 for non-POST requests", %{server: server} do
      # Create a test conn with a GET request
      conn = conn(:get, "/")
      
      # Call the controller
      conn = Controller.call(conn, server: server)
      
      # Assert the response
      assert conn.status == 405
    end
  end
end
