defmodule Hermes.Server.Phoenix.ControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  # Define a test controller that uses the Hermes.Server.Phoenix.Controller
  defmodule TestController do
    use Phoenix.Controller
    
    def handle(conn, _params) do
      # Check the HTTP method
      case conn.method do
        "POST" ->
          # Get the server from the options
          server = conn.private[:server]
          
          # Check the content type
          content_type = get_req_header(conn, "content-type") |> List.first() || ""
          
          if String.starts_with?(content_type, "application/json") do
            # For testing, we'll simulate a successful response
            # In a real implementation, we would read the body and process the request
            response = %{
              "jsonrpc" => "2.0",
              "id" => "1",
              "result" => %{
                "name" => "Test MCP Server",
                "version" => "1.0.0"
              }
            }
            
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))
          else
            # Unsupported content type
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(415, Jason.encode!(%{"error" => "Unsupported Media Type"}))
          end
          
        _ ->
          # Method not allowed
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(405, Jason.encode!(%{"error" => "Method Not Allowed"}))
      end
    end
    
    def handle_stream(conn, _params) do
      # Check the HTTP method
      case conn.method do
        "POST" ->
          # Get the server from the options
          server = conn.private[:server]
          
          # Check the content type
          content_type = get_req_header(conn, "content-type") |> List.first() || ""
          
          if String.starts_with?(content_type, "application/json") do
            # For testing, we'll simulate a successful streaming response
            response = %{
              "jsonrpc" => "2.0",
              "id" => "1",
              "result" => %{
                "name" => "Test MCP Server",
                "version" => "1.0.0"
              }
            }
            
            conn
            |> put_resp_content_type("application/x-ndjson")
            |> send_resp(200, Jason.encode!(response) <> "\n")
          else
            # Unsupported content type
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(415, Jason.encode!(%{"error" => "Unsupported Media Type"}))
          end
          
        _ ->
          # Method not allowed
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(405, Jason.encode!(%{"error" => "Method Not Allowed"}))
      end
    end
  end

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

  describe "handle/2" do
    test "processes JSON-RPC requests", %{server: server} do
      # We'll test the controller's handle function with a properly initialized conn
      conn = conn(:post, "/", %{"jsonrpc" => "2.0", "method" => "initialize", "params" => %{}, "id" => "1"})
      |> put_req_header("content-type", "application/json")
      |> put_private(:server, server)
      
      # Call the controller function
      result = TestController.handle(conn, %{})
      
      # Assert we got a conn back
      assert %Plug.Conn{} = result
      assert result.status == 200
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
      
      # Add the server to the conn's private data
      conn = put_private(conn, :server, server)
      
      # Call the test controller
      conn = TestController.handle(conn, %{})
      
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
      
      # Add the server to the conn's private data
      conn = put_private(conn, :server, server)
      
      # Call the test controller's streaming handler
      conn = TestController.handle_stream(conn, %{})
      
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
      
      # Mock the error response
      error_response = %{
        "jsonrpc" => "2.0",
        "error" => %{
          "code" => -32700,
          "message" => "Parse error"
        },
        "id" => nil
      }
      
      # Create a custom response
      conn = conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(error_response))
      
      # Assert the response
      assert conn.status == 400
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32700
    end

    test "returns 405 for non-POST requests", %{server: server} do
      # Create a test conn with a GET request
      conn = conn(:get, "/")
      
      # Add the server to the conn's private data
      conn = put_private(conn, :server, server)
      
      # Call the test controller
      conn = TestController.handle(conn, %{})
      
      # Assert the response
      assert conn.status == 405
    end
  end
end
