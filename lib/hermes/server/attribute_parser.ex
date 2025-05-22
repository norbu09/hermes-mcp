defmodule Hermes.Server.AttributeParser do
  @moduledoc """
  Utilities for parsing module attributes to extract MCP component definitions.
  
  This module provides functions for extracting tool, resource, and prompt
  definitions from module attributes, particularly from @doc attributes
  with special MCP-specific annotations.
  
  ## MCP Annotations
  
  The following annotations are supported in @doc attributes:
  
  - `@mcp_tool <name>` - Marks a function as an MCP tool with the given name
  - `@mcp_param <name> <type> [options]` - Defines a parameter for an MCP tool
  - `@mcp_resource <uri>` - Marks a function as an MCP resource with the given URI
  - `@mcp_mime_type <type>` - Defines the MIME type for an MCP resource
  - `@mcp_prompt <name>` - Marks a function as an MCP prompt with the given name
  - `@mcp_arg <name> [options]` - Defines an argument for an MCP prompt
  
  ## Examples
  
  ```elixir
  defmodule MyApp.MCP.CalculatorTool do
    @doc \"\"\"
    Perform basic arithmetic operations.
    
    @mcp_tool calculate
    @mcp_param operation String [required: true, enum: ["add", "subtract", "multiply", "divide"]]
    @mcp_param x Number [required: true]
    @mcp_param y Number [required: true]
    \"\"\"
    def handle(%{"operation" => "add", "x" => x, "y" => y}, _ctx) do
      {:ok, x + y}
    end
  end
  ```
  """
  
  require Logger
  
  @doc """
  Extracts tool definitions from a module.
  
  Scans the module for functions with @doc attributes containing
  @mcp_tool annotations and extracts tool definitions from them.
  
  ## Examples
  
      iex> Hermes.Server.AttributeParser.extract_tools(MyApp.MCP.CalculatorTool)
      [
        %{
          name: "calculate",
          description: "Perform basic arithmetic operations.",
          parameters: [
            %{
              name: "operation",
              type: "string",
              description: "Operation to perform",
              required: true,
              enum: ["add", "subtract", "multiply", "divide"]
            },
            %{
              name: "x",
              type: "number",
              description: "First number",
              required: true
            },
            %{
              name: "y",
              type: "number",
              description: "Second number",
              required: true
            }
          ],
          handler: &MyApp.MCP.CalculatorTool.handle/2
        }
      ]
  """
  @spec extract_tools(module()) :: [map()]
  def extract_tools(module) when is_atom(module) do
    # Get all functions with documentation
    docs = Code.fetch_docs(module)
    
    case docs do
      {:docs_v1, _, _, _, _, _, function_docs} ->
        # Filter functions with @mcp_tool annotations
        function_docs
        |> Enum.filter(fn {_, _, _, doc, _} -> 
          is_map(doc) and doc[:doc] != nil and String.contains?(doc[:doc], "@mcp_tool")
        end)
        |> Enum.map(fn {_, name, arity, doc, _} ->
          # Parse the doc attribute for MCP metadata
          metadata = parse_doc_attribute(doc[:doc])
          
          # Build the tool definition
          %{
            name: Map.get(metadata, "tool_name", to_string(name)),
            description: Map.get(metadata, "description", ""),
            parameters: Map.get(metadata, "parameters", []),
            handler: Function.capture(module, name, arity)
          }
        end)
        
      _ ->
        Logger.warning("Failed to fetch docs for module #{inspect(module)}")
        []
    end
  end
  
  @doc """
  Extracts resource definitions from a module.
  
  Scans the module for functions with @doc attributes containing
  @mcp_resource annotations and extracts resource definitions from them.
  
  ## Examples
  
      iex> Hermes.Server.AttributeParser.extract_resources(MyApp.MCP.ReadmeResource)
      [
        %{
          uri: "docs://readme",
          name: "Project README",
          description: "The project's README file",
          mime_type: "text/markdown",
          reader: &MyApp.MCP.ReadmeResource.read/2
        }
      ]
  """
  @spec extract_resources(module()) :: [map()]
  def extract_resources(module) when is_atom(module) do
    # Get all functions with documentation
    docs = Code.fetch_docs(module)
    
    case docs do
      {:docs_v1, _, _, _, _, _, function_docs} ->
        # Filter functions with @mcp_resource annotations
        function_docs
        |> Enum.filter(fn {_, _, _, doc, _} -> 
          is_map(doc) and doc[:doc] != nil and String.contains?(doc[:doc], "@mcp_resource")
        end)
        |> Enum.map(fn {_, name, arity, doc, _} ->
          # Parse the doc attribute for MCP metadata
          metadata = parse_doc_attribute(doc[:doc])
          
          # Build the resource definition
          %{
            uri: Map.get(metadata, "resource_uri", ""),
            name: Map.get(metadata, "name", to_string(name)),
            description: Map.get(metadata, "description", ""),
            mime_type: Map.get(metadata, "mime_type", "text/plain"),
            reader: Function.capture(module, name, arity)
          }
        end)
        
      _ ->
        Logger.warning("Failed to fetch docs for module #{inspect(module)}")
        []
    end
  end
  
  @doc """
  Extracts prompt definitions from a module.
  
  Scans the module for functions with @doc attributes containing
  @mcp_prompt annotations and extracts prompt definitions from them.
  
  ## Examples
  
      iex> Hermes.Server.AttributeParser.extract_prompts(MyApp.MCP.GreetingPrompt)
      [
        %{
          name: "greeting",
          description: "A friendly greeting prompt",
          arguments: [
            %{
              name: "name",
              description: "Name of the person to greet",
              required: false
            }
          ],
          handler: &MyApp.MCP.GreetingPrompt.get/2
        }
      ]
  """
  @spec extract_prompts(module()) :: [map()]
  def extract_prompts(module) when is_atom(module) do
    # Get all functions with documentation
    docs = Code.fetch_docs(module)
    
    case docs do
      {:docs_v1, _, _, _, _, _, function_docs} ->
        # Filter functions with @mcp_prompt annotations
        function_docs
        |> Enum.filter(fn {_, _, _, doc, _} -> 
          is_map(doc) and doc[:doc] != nil and String.contains?(doc[:doc], "@mcp_prompt")
        end)
        |> Enum.map(fn {_, name, arity, doc, _} ->
          # Parse the doc attribute for MCP metadata
          metadata = parse_doc_attribute(doc[:doc])
          
          # Build the prompt definition
          %{
            name: Map.get(metadata, "prompt_name", to_string(name)),
            description: Map.get(metadata, "description", ""),
            arguments: Map.get(metadata, "arguments", []),
            handler: Function.capture(module, name, arity)
          }
        end)
        
      _ ->
        Logger.warning("Failed to fetch docs for module #{inspect(module)}")
        []
    end
  end
  
  @doc """
  Parses a doc attribute for MCP metadata.
  
  Extracts MCP-specific annotations from a doc string and returns
  a map of metadata.
  
  ## Examples
  
      iex> doc = \"\"\"
      ...> Perform basic arithmetic operations.
      ...> 
      ...> @mcp_tool calculate
      ...> @mcp_param operation String [required: true, enum: ["add", "subtract", "multiply", "divide"]]
      ...> @mcp_param x Number [required: true]
      ...> @mcp_param y Number [required: true]
      ...> \"\"\"
      iex> Hermes.Server.AttributeParser.parse_doc_attribute(doc)
      %{
        "description" => "Perform basic arithmetic operations.",
        "tool_name" => "calculate",
        "parameters" => [
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
      }
  """
  @spec parse_doc_attribute(String.t()) :: map()
  def parse_doc_attribute(doc) when is_binary(doc) do
    # Extract description (first paragraph)
    description = 
      case String.split(doc, ~r/\n\s*\n/, parts: 2) do
        [first | _] -> String.trim(first)
        [] -> ""
      end
    
    # Initialize metadata with description
    metadata = %{"description" => description}
    
    # Extract tool name
    metadata = 
      case Regex.run(~r/@mcp_tool\s+([^\s\n]+)/, doc) do
        [_, tool_name] -> Map.put(metadata, "tool_name", tool_name)
        _ -> metadata
      end
    
    # Extract resource URI
    metadata = 
      case Regex.run(~r/@mcp_resource\s+([^\s\n]+)/, doc) do
        [_, resource_uri] -> Map.put(metadata, "resource_uri", resource_uri)
        _ -> metadata
      end
    
    # Extract MIME type
    metadata = 
      case Regex.run(~r/@mcp_mime_type\s+([^\s\n]+)/, doc) do
        [_, mime_type] -> Map.put(metadata, "mime_type", mime_type)
        _ -> metadata
      end
    
    # Extract prompt name
    metadata = 
      case Regex.run(~r/@mcp_prompt\s+([^\s\n]+)/, doc) do
        [_, prompt_name] -> Map.put(metadata, "prompt_name", prompt_name)
        _ -> metadata
      end
    
    # Extract parameters
    parameters = 
      Regex.scan(~r/@mcp_param\s+([^\s]+)\s+([^\s]+)(?:\s+\[([^\]]+)\])?/, doc)
      |> Enum.map(fn
        [_, name, type] ->
          %{
            "name" => name,
            "type" => String.downcase(type),
            "description" => "Parameter #{name}"
          }
        [_, name, type, options] ->
          # Parse options
          opts = parse_options(options)
          
          %{
            "name" => name,
            "type" => String.downcase(type),
            "description" => Map.get(opts, "description", "Parameter #{name}")
          }
          |> Map.merge(opts)
      end)
    
    # Add parameters to metadata if any
    metadata = 
      if parameters != [], do: Map.put(metadata, "parameters", parameters), else: metadata
    
    # Extract arguments
    arguments = 
      Regex.scan(~r/@mcp_arg\s+([^\s]+)(?:\s+\[([^\]]+)\])?/, doc)
      |> Enum.map(fn
        [_, name] ->
          %{
            "name" => name,
            "description" => "Argument #{name}"
          }
        [_, name, options] ->
          # Parse options
          opts = parse_options(options)
          
          %{
            "name" => name,
            "description" => Map.get(opts, "description", "Argument #{name}")
          }
          |> Map.merge(opts)
      end)
    
    # Add arguments to metadata if any
    if arguments != [], do: Map.put(metadata, "arguments", arguments), else: metadata
  end
  
  def parse_doc_attribute(_), do: %{}
  
  # Helper function to parse options
  defp parse_options(options_str) do
    options_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn option ->
      case String.split(option, ":", parts: 2) do
        [key, value] -> {key, parse_value(value)}
        [key] -> {key, true}
      end
    end)
    |> Enum.into(%{})
  end
  
  # Helper function to parse option values
  defp parse_value(value) do
    value = String.trim(value)
    
    cond do
      value == "true" -> true
      value == "false" -> false
      String.starts_with?(value, "[") and String.ends_with?(value, "]") ->
        value
        |> String.slice(1..-2)
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn item ->
          # Remove quotes if present
          item = 
            if String.starts_with?(item, "\"") and String.ends_with?(item, "\"") do
              String.slice(item, 1..-2)
            else
              item
            end
          
          # Try to parse as number or keep as string
          case Integer.parse(item) do
            {int, ""} -> int
            _ ->
              case Float.parse(item) do
                {float, ""} -> float
                _ -> item
              end
          end
        end)
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2)
      true ->
        # Try to parse as number or keep as string
        case Integer.parse(value) do
          {int, ""} -> int
          _ ->
            case Float.parse(value) do
              {float, ""} -> float
              _ -> value
            end
        end
    end
  end
end
