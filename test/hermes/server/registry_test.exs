defmodule Hermes.Server.RegistryTest do
  use ExUnit.Case, async: true
  alias Hermes.Server.Registry

  setup do
    # Start a registry for each test
    registry_name = :"#{__MODULE__}.Registry.#{System.unique_integer([:positive])}"
    {:ok, pid} = Registry.start_link(name: registry_name)
    
    # Return the registry name for use in tests
    %{registry: registry_name, pid: pid}
  end

  describe "start_link/1" do
    test "starts a registry process with the given name", %{registry: registry} do
      assert Process.whereis(registry) != nil
      assert Process.alive?(Process.whereis(registry))
    end
  end

  describe "register_tool/2" do
    test "registers a tool module", %{registry: registry} do
      defmodule TestTool do
        @behaviour Hermes.Server.Tool

        @impl true
        def name, do: "test_tool"

        @impl true
        def description, do: "Test tool"

        @impl true
        def parameters, do: []

        @impl true
        def handle(_params, _context), do: {:ok, "result"}
      end

      assert :ok = Registry.register_tool(registry, TestTool)
      assert [TestTool] = Registry.get_tools(registry)
    end

    test "returns error for invalid tool module", %{registry: registry} do
      defmodule InvalidTool do
        def some_function, do: "not a tool"
      end

      assert {:error, :invalid_tool} = Registry.register_tool(registry, InvalidTool)
      assert [] = Registry.get_tools(registry)
    end
  end

  describe "register_resource/2" do
    test "registers a resource module", %{registry: registry} do
      defmodule TestResource do
        @behaviour Hermes.Server.Resource

        @impl true
        def uri, do: "test://resource"

        @impl true
        def name, do: "Test Resource"

        @impl true
        def description, do: "Test resource"

        @impl true
        def mime_type, do: "text/plain"

        @impl true
        def read(_params, _context), do: {:ok, "content"}
      end

      assert :ok = Registry.register_resource(registry, TestResource)
      assert [TestResource] = Registry.get_resources(registry)
    end

    test "returns error for invalid resource module", %{registry: registry} do
      defmodule InvalidResource do
        def some_function, do: "not a resource"
      end

      assert {:error, :invalid_resource} = Registry.register_resource(registry, InvalidResource)
      assert [] = Registry.get_resources(registry)
    end
  end

  describe "register_prompt/2" do
    test "registers a prompt module", %{registry: registry} do
      defmodule TestPrompt do
        @behaviour Hermes.Server.Prompt

        @impl true
        def name, do: "test_prompt"

        @impl true
        def description, do: "Test prompt"

        @impl true
        def arguments, do: []

        @impl true
        def get(_params, _context), do: {:ok, "prompt"}
      end

      assert :ok = Registry.register_prompt(registry, TestPrompt)
      assert [TestPrompt] = Registry.get_prompts(registry)
    end

    test "returns error for invalid prompt module", %{registry: registry} do
      defmodule InvalidPrompt do
        def some_function, do: "not a prompt"
      end

      assert {:error, :invalid_prompt} = Registry.register_prompt(registry, InvalidPrompt)
      assert [] = Registry.get_prompts(registry)
    end
  end

  describe "discover_components/2" do
    test "discovers components by module prefix", %{registry: registry} do
      defmodule Test.MCP.TestTool do
        @behaviour Hermes.Server.Tool

        @impl true
        def name, do: "test_tool"

        @impl true
        def description, do: "Test tool"

        @impl true
        def parameters, do: []

        @impl true
        def handle(_params, _context), do: {:ok, "result"}
      end

      defmodule Test.MCP.TestResource do
        @behaviour Hermes.Server.Resource

        @impl true
        def uri, do: "test://resource"

        @impl true
        def name, do: "Test Resource"

        @impl true
        def description, do: "Test resource"

        @impl true
        def mime_type, do: "text/plain"

        @impl true
        def read(_params, _context), do: {:ok, "content"}
      end

      defmodule Test.MCP.TestPrompt do
        @behaviour Hermes.Server.Prompt

        @impl true
        def name, do: "test_prompt"

        @impl true
        def description, do: "Test prompt"

        @impl true
        def arguments, do: []

        @impl true
        def get(_params, _context), do: {:ok, "prompt"}
      end

      # Discover components with the Test.MCP prefix
      assert {:ok, components} = Registry.discover_components(registry, Test.MCP)
      
      assert Enum.member?(components.tools, Test.MCP.TestTool)
      assert Enum.member?(components.resources, Test.MCP.TestResource)
      assert Enum.member?(components.prompts, Test.MCP.TestPrompt)
      
      # Verify the components were registered
      assert Enum.member?(Registry.get_tools(registry), Test.MCP.TestTool)
      assert Enum.member?(Registry.get_resources(registry), Test.MCP.TestResource)
      assert Enum.member?(Registry.get_prompts(registry), Test.MCP.TestPrompt)
    end

    test "discovers components with attribute annotations", %{registry: registry} do
      defmodule Test.MCP.AttributeTool do
        @doc """
        Test tool with attributes.
        
        @mcp_tool attribute_tool
        @mcp_param x Number [required: true]
        """
        def handle(_params, _context), do: {:ok, "result"}
      end

      # Discover components with the Test.MCP prefix
      assert {:ok, components} = Registry.discover_components(registry, Test.MCP)
      
      # Verify the attribute-based tool was discovered
      assert Enum.any?(components.tools, fn module -> 
        to_string(module) =~ "AttributeTool"
      end)
    end
  end
end
