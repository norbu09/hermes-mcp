defmodule Hermes.Server.Phoenix.PlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Hermes.Server.Phoenix.AuthPlug

  describe "init/1" do
    test "initializes plug options" do
      opts = AuthPlug.init(token: "test_token")
      assert opts[:token] == "test_token"
    end

    test "uses default options when not provided" do
      opts = AuthPlug.init([])
      assert opts[:token] == nil
    end
  end

  describe "call/2" do
    test "passes through when no token is required" do
      # Create a test conn
      conn = conn(:post, "/")
      
      # Call the plug with no token requirement
      conn = AuthPlug.call(conn, [])
      
      # Assert the conn passes through unchanged
      refute conn.halted
    end

    test "passes through when token matches" do
      # Create a test conn with the correct token
      conn = conn(:post, "/")
      |> put_req_header("authorization", "Bearer test_token")
      
      # Call the plug with token requirement
      conn = AuthPlug.call(conn, token: "test_token")
      
      # Assert the conn passes through unchanged
      refute conn.halted
    end

    test "halts with 401 when token is missing" do
      # Create a test conn with no token
      conn = conn(:post, "/")
      
      # Call the plug with token requirement
      conn = AuthPlug.call(conn, token: "test_token")
      
      # Assert the conn is halted with 401
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32001
      assert response["error"]["message"] =~ "Authentication required"
    end

    test "halts with 401 when token is invalid" do
      # Create a test conn with an invalid token
      conn = conn(:post, "/")
      |> put_req_header("authorization", "Bearer invalid_token")
      
      # Call the plug with token requirement
      conn = AuthPlug.call(conn, token: "test_token")
      
      # Assert the conn is halted with 401
      assert conn.halted
      assert conn.status == 401
      
      response = Jason.decode!(conn.resp_body)
      assert response["error"]["code"] == -32001
      assert response["error"]["message"] =~ "Invalid token"
    end

    test "supports function-based token validation" do
      # Define a token validator function
      validator = fn token -> token == "valid_token" end
      
      # Create test conns with valid and invalid tokens
      valid_conn = conn(:post, "/")
      |> put_req_header("authorization", "Bearer valid_token")
      
      invalid_conn = conn(:post, "/")
      |> put_req_header("authorization", "Bearer invalid_token")
      
      # Call the plug with the validator function
      valid_result = AuthPlug.call(valid_conn, validator: validator)
      invalid_result = AuthPlug.call(invalid_conn, validator: validator)
      
      # Assert the results
      refute valid_result.halted
      assert invalid_result.halted
      assert invalid_result.status == 401
    end
  end
end
