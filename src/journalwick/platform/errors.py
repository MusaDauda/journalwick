"""Safe configuration errors shared by process setup and API boundaries."""


class RuntimeConfigurationError(RuntimeError):
    """A required runtime mode is missing or not supported by this build."""
