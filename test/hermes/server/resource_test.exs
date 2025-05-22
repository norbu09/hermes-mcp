defmodule Hermes.Server.ResourceTest do
  use ExUnit.Case, async: true
  
  alias Hermes.Server.Resource
  
  # Define a test resource
  defmodule TestResource do
    use Hermes.Server.Resource
    
    @impl true
    def uri, do: "test://resource"
    
    @impl true
    def mime_type, do: "text/plain"
    
    @impl true
    def read(_params, _ctx) do
      {:ok, "Test resource content"}
    end
  end
  
  # Define a test resource with custom implementations
  defmodule CustomResource do
    use Hermes.Server.Resource
    
    @impl true
    def uri, do: "docs://readme"
    
    @impl true
    def name, do: "Project README"
    
    @impl true
    def description, do: "The project's README file"
    
    @impl true
    def mime_type, do: "text/markdown"
    
    @impl true
    def read(params, _ctx) do
      case Map.get(params, "version") do
        "1.0" -> {:ok, "# Version 1.0\n\nThis is the README for version 1.0"}
        "2.0" -> {:ok, "# Version 2.0\n\nThis is the README for version 2.0"}
        _ -> {:ok, "# Default Version\n\nThis is the default README"}
      end
    end
  end
  
  describe "default implementations" do
    test "name is derived from module name" do
      assert TestResource.name() == "test-resource"
    end
    
    test "description is provided" do
      assert TestResource.description() =~ "TestResource"
    end
  end
  
  describe "custom implementations" do
    test "name is customized" do
      assert CustomResource.name() == "Project README"
    end
    
    test "description is customized" do
      assert CustomResource.description() == "The project's README file"
    end
    
    test "uri is customized" do
      assert CustomResource.uri() == "docs://readme"
    end
    
    test "mime_type is customized" do
      assert CustomResource.mime_type() == "text/markdown"
    end
  end
  
  describe "read function" do
    test "basic read function works" do
      assert {:ok, "Test resource content"} = TestResource.read(%{}, %{})
    end
    
    test "custom read function works with default version" do
      assert {:ok, content} = CustomResource.read(%{}, %{})
      assert content =~ "Default Version"
    end
    
    test "custom read function works with version 1.0" do
      assert {:ok, content} = CustomResource.read(%{"version" => "1.0"}, %{})
      assert content =~ "Version 1.0"
    end
    
    test "custom read function works with version 2.0" do
      assert {:ok, content} = CustomResource.read(%{"version" => "2.0"}, %{})
      assert content =~ "Version 2.0"
    end
  end
end
