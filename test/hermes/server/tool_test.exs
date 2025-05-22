defmodule Hermes.Server.ToolTest do
  use ExUnit.Case, async: true
  
  alias Hermes.Server.Tool
  
  # Define a test tool
  defmodule TestTool do
    use Hermes.Server.Tool
    
    @impl true
    def handle(%{"x" => x, "y" => y}, _ctx) do
      {:ok, x + y}
    end
  end
  
  # Define a test tool with custom implementations
  defmodule CustomTool do
    use Hermes.Server.Tool
    
    @impl true
    def name, do: "custom-calculator"
    
    @impl true
    def description, do: "A custom calculator tool"
    
    @impl true
    def parameters do
      [
        %{
          "name" => "operation",
          "type" => "string",
          "description" => "Operation to perform",
          "required" => true,
          "enum" => ["add", "subtract", "multiply", "divide"]
        },
        %{
          "name" => "x",
          "type" => "number",
          "description" => "First number",
          "required" => true
        },
        %{
          "name" => "y",
          "type" => "number",
          "description" => "Second number",
          "required" => true
        }
      ]
    end
    
    @impl true
    def handle(%{"operation" => "add", "x" => x, "y" => y}, _ctx), do: {:ok, x + y}
    def handle(%{"operation" => "subtract", "x" => x, "y" => y}, _ctx), do: {:ok, x - y}
    def handle(%{"operation" => "multiply", "x" => x, "y" => y}, _ctx), do: {:ok, x * y}
    def handle(%{"operation" => "divide", "x" => _, "y" => 0}, _ctx), do: {:error, "Cannot divide by zero"}
    def handle(%{"operation" => "divide", "x" => x, "y" => y}, _ctx), do: {:ok, x / y}
  end
  
  describe "default implementations" do
    test "name is derived from module name" do
      assert TestTool.name() == "test-tool"
    end
    
    test "description is provided" do
      assert TestTool.description() =~ "TestTool"
    end
    
    test "parameters is an empty list" do
      assert TestTool.parameters() == []
    end
  end
  
  describe "custom implementations" do
    test "name is customized" do
      assert CustomTool.name() == "custom-calculator"
    end
    
    test "description is customized" do
      assert CustomTool.description() == "A custom calculator tool"
    end
    
    test "parameters are customized" do
      params = CustomTool.parameters()
      assert length(params) == 3
      assert Enum.find(params, fn p -> p["name"] == "operation" end)
      assert Enum.find(params, fn p -> p["name"] == "x" end)
      assert Enum.find(params, fn p -> p["name"] == "y" end)
    end
  end
  
  describe "handle function" do
    test "basic handle function works" do
      assert {:ok, 5} = TestTool.handle(%{"x" => 2, "y" => 3}, %{})
    end
    
    test "custom handle function works for add" do
      assert {:ok, 5} = CustomTool.handle(%{"operation" => "add", "x" => 2, "y" => 3}, %{})
    end
    
    test "custom handle function works for subtract" do
      assert {:ok, -1} = CustomTool.handle(%{"operation" => "subtract", "x" => 2, "y" => 3}, %{})
    end
    
    test "custom handle function works for multiply" do
      assert {:ok, 6} = CustomTool.handle(%{"operation" => "multiply", "x" => 2, "y" => 3}, %{})
    end
    
    test "custom handle function works for divide" do
      assert {:ok, 2.0} = CustomTool.handle(%{"operation" => "divide", "x" => 6, "y" => 3}, %{})
    end
    
    test "custom handle function returns error for divide by zero" do
      assert {:error, "Cannot divide by zero"} = CustomTool.handle(%{"operation" => "divide", "x" => 6, "y" => 0}, %{})
    end
  end
end
