defmodule Hermes.Server.AttributeParserTest do
  use ExUnit.Case, async: true
  alias Hermes.Server.AttributeParser

  describe "parse_doc_attribute/1" do
    test "extracts description" do
      doc = """
      This is a description.

      Some other text.
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert result["description"] == "This is a description."
    end

    test "extracts tool name" do
      doc = """
      Tool description.

      @mcp_tool calculator
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert result["tool_name"] == "calculator"
    end

    test "extracts resource URI" do
      doc = """
      Resource description.

      @mcp_resource docs://readme
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert result["resource_uri"] == "docs://readme"
    end

    test "extracts MIME type" do
      doc = """
      Resource description.

      @mcp_mime_type text/markdown
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert result["mime_type"] == "text/markdown"
    end

    test "extracts prompt name" do
      doc = """
      Prompt description.

      @mcp_prompt greeting
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert result["prompt_name"] == "greeting"
    end

    test "extracts parameters" do
      doc = """
      Tool description.

      @mcp_tool calculator
      @mcp_param x Number [required: true]
      @mcp_param y Number [required: true, description: "Second operand"]
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert length(result["parameters"]) == 2
      
      [param1, param2] = result["parameters"]
      assert param1["name"] == "x"
      assert param1["type"] == "number"
      assert param1["required"] == true
      
      assert param2["name"] == "y"
      assert param2["type"] == "number"
      assert param2["required"] == true
      assert param2["description"] == "Second operand"
    end

    test "extracts arguments" do
      doc = """
      Prompt description.

      @mcp_prompt greeting
      @mcp_arg name [required: false, description: "Name to greet"]
      """

      result = AttributeParser.parse_doc_attribute(doc)
      assert length(result["arguments"]) == 1
      
      [arg] = result["arguments"]
      assert arg["name"] == "name"
      assert arg["required"] == false
      assert arg["description"] == "Name to greet"
    end
  end

  describe "extract_metadata/1" do
    # For these tests, we'll define some test modules in the test itself
    
    test "identifies a module with tool annotations" do
      defmodule TestToolModule do
        @doc """
        Test tool.
        
        @mcp_tool test_tool
        """
        def handle(_params, _context), do: {:ok, "result"}
      end

      result = AttributeParser.extract_metadata(TestToolModule)
      assert result.tool == true
      assert result.resource == false
      assert result.prompt == false
    end

    test "identifies a module with resource annotations" do
      defmodule TestResourceModule do
        @doc """
        Test resource.
        
        @mcp_resource test://resource
        """
        def read(_params, _context), do: {:ok, "content"}
      end

      result = AttributeParser.extract_metadata(TestResourceModule)
      assert result.tool == false
      assert result.resource == true
      assert result.prompt == false
    end

    test "identifies a module with prompt annotations" do
      defmodule TestPromptModule do
        @doc """
        Test prompt.
        
        @mcp_prompt test_prompt
        """
        def get(_params, _context), do: {:ok, "prompt"}
      end

      result = AttributeParser.extract_metadata(TestPromptModule)
      assert result.tool == false
      assert result.resource == false
      assert result.prompt == true
    end
  end

  describe "extract_tools/1" do
    test "extracts tool definitions from a module" do
      defmodule TestCalculatorTool do
        @doc """
        Perform basic arithmetic operations.
        
        @mcp_tool calculate
        @mcp_param operation String [required: true, enum: ["add", "subtract", "multiply", "divide"]]
        @mcp_param x Number [required: true]
        @mcp_param y Number [required: true]
        """
        def handle(%{"operation" => "add", "x" => x, "y" => y}, _ctx) do
          {:ok, x + y}
        end
      end

      [tool] = AttributeParser.extract_tools(TestCalculatorTool)
      assert tool.name == "calculate"
      assert tool.description == "Perform basic arithmetic operations."
      assert length(tool.parameters) == 3
      
      [op_param, x_param, y_param] = tool.parameters
      assert op_param["name"] == "operation"
      assert op_param["type"] == "string"
      assert op_param["required"] == true
      assert op_param["enum"] == ["add", "subtract", "multiply", "divide"]
      
      assert x_param["name"] == "x"
      assert x_param["type"] == "number"
      assert x_param["required"] == true
      
      assert y_param["name"] == "y"
      assert y_param["type"] == "number"
      assert y_param["required"] == true
      
      assert is_function(tool.handler, 2)
    end
  end
end
