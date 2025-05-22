defmodule Hermes.Server.PromptTest do
  use ExUnit.Case, async: true
  
  alias Hermes.Server.Prompt
  
  # Define a test prompt
  defmodule TestPrompt do
    use Hermes.Server.Prompt
    
    @impl true
    def get(_args, _ctx) do
      messages = [
        %{
          role: "assistant",
          content: %{
            type: "text",
            text: "Hello there!"
          }
        }
      ]
      
      {:ok, %{title: "Test Prompt", messages: messages}}
    end
  end
  
  # Define a test prompt with custom implementations
  defmodule CustomPrompt do
    use Hermes.Server.Prompt
    
    @impl true
    def name, do: "greeting"
    
    @impl true
    def description, do: "A friendly greeting prompt"
    
    @impl true
    def arguments do
      [
        %{
          "name" => "name",
          "description" => "Name of the person to greet",
          "required" => false
        }
      ]
    end
    
    @impl true
    def get(%{"name" => name}, _ctx) when is_binary(name) do
      messages = [
        %{
          role: "assistant",
          content: %{
            type: "text",
            text: "Hello, #{name}! How can I help you today?"
          }
        }
      ]
      
      {:ok, %{title: "A friendly greeting", messages: messages}}
    end
    
    def get(_args, _ctx) do
      messages = [
        %{
          role: "assistant",
          content: %{
            type: "text",
            text: "Hello there! How can I help you today?"
          }
        }
      ]
      
      {:ok, %{title: "A friendly greeting", messages: messages}}
    end
  end
  
  describe "default implementations" do
    test "name is derived from module name" do
      assert TestPrompt.name() == "test-prompt"
    end
    
    test "description is provided" do
      assert TestPrompt.description() =~ "TestPrompt"
    end
    
    test "arguments is an empty list" do
      assert TestPrompt.arguments() == []
    end
  end
  
  describe "custom implementations" do
    test "name is customized" do
      assert CustomPrompt.name() == "greeting"
    end
    
    test "description is customized" do
      assert CustomPrompt.description() == "A friendly greeting prompt"
    end
    
    test "arguments are customized" do
      args = CustomPrompt.arguments()
      assert length(args) == 1
      assert hd(args)["name"] == "name"
      assert hd(args)["description"] == "Name of the person to greet"
      assert hd(args)["required"] == false
    end
  end
  
  describe "get function" do
    test "basic get function works" do
      assert {:ok, %{title: "Test Prompt", messages: messages}} = TestPrompt.get(%{}, %{})
      assert length(messages) == 1
      assert hd(messages).role == "assistant"
      assert hd(messages).content.text == "Hello there!"
    end
    
    test "custom get function works with name" do
      assert {:ok, %{title: "A friendly greeting", messages: messages}} = CustomPrompt.get(%{"name" => "John"}, %{})
      assert length(messages) == 1
      assert hd(messages).role == "assistant"
      assert hd(messages).content.text == "Hello, John! How can I help you today?"
    end
    
    test "custom get function works without name" do
      assert {:ok, %{title: "A friendly greeting", messages: messages}} = CustomPrompt.get(%{}, %{})
      assert length(messages) == 1
      assert hd(messages).role == "assistant"
      assert hd(messages).content.text == "Hello there! How can I help you today?"
    end
  end
end
