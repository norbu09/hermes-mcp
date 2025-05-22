# Registry Refactor for MCP Server Implementation

## Overview

This document describes the refactoring of the component discovery and registration system in the Hermes MCP server implementation. The changes replace the "magical" automatic attribute-based component discovery with a more explicit registry-based approach.

## Changes Made

### 1. Registry Module Enhancements

- Added a new `register_attribute_component/3` function to the Registry module to handle attribute-based components explicitly:
  ```elixir
  def register_attribute_component(registry \\ __MODULE__, module, metadata) do
    GenServer.call(registry, {:register_attribute_component, module, metadata})
  end
  ```

- Updated the `discover_components/2` function to focus only on behavior-based components, removing the attribute-based discovery logic from this function.

- Added a new handler for the `register_attribute_component` call that properly registers components based on their metadata.

### 2. Server Module Updates

- Replaced the direct attribute-based component discovery with explicit registration through the registry:
  ```elixir
  # Then register attribute-based components explicitly
  register_attribute_components(registry_name, state.module_prefix)
  ```

- Created a new `register_attribute_components/2` function that extracts metadata from modules and registers them with the registry.

- Removed the duplicate discovery logic from the Server module, relying entirely on the registry for component management.

### 3. AttributeParser Updates

- Fixed String.slice warnings by updating the deprecated syntax:
  ```elixir
  # Old syntax
  String.slice(value, 1..-2)
  
  # New syntax
  String.slice(value, 1..-2//1)
  ```

### 4. Test Fixes

- Updated the registry test to use the new explicit registration approach.
- Fixed the Phoenix router test to use the fully qualified module name.
- Fixed the Phoenix controller test by properly setting up the Plug.Conn for testing.
- Fixed the SSE test by ensuring the Bypass server properly receives and responds to the request.

## Benefits

1. **Explicit Component Registration**: The new approach makes component registration more explicit and less "magical", which aligns with Elixir's philosophy.

2. **Better Control**: The registry-based approach provides better control over component registration and discovery.

3. **Improved Maintainability**: The code is more maintainable because the component registration is more explicit and easier to understand.

4. **Reduced Complexity**: By centralizing component management in the registry, we've reduced the complexity of the server implementation.

## Future Considerations

- Consider adding more helper functions to simplify component registration.
- Add more comprehensive documentation for the registry-based approach.
- Consider adding validation for registered components to ensure they meet the required interface.
