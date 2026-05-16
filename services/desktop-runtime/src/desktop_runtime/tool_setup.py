from desktop_runtime.tool_registry import ToolRegistry
from desktop_runtime.tools.desktop_tools import take_screenshot
from desktop_runtime.tools.file_tools import file_read, file_write, list_directory, read_file
from desktop_runtime.tools.run_applescript import run_applescript
from desktop_runtime.tools.shell_tools import run_shell_command
from desktop_runtime.tools.web_tools import web_fetch, web_search


def register_default_tools(registry: ToolRegistry) -> None:
    """Register all built-in tools. Call once at startup before worker.start()."""
    registry.register("read_file", read_file)
    registry.register("file_read", file_read)
    registry.register("file_write", file_write)
    registry.register("list_directory", list_directory)
    registry.register("run_shell_command", run_shell_command)
    registry.register("web_fetch", web_fetch)
    registry.register("web_search", web_search)
    registry.register("take_screenshot", take_screenshot)
    registry.register("run_applescript", run_applescript)
