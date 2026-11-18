"""Useful public failure messages without leaking provider bodies or credentials."""
from anthropic import AuthenticationError, PermissionDeniedError, RateLimitError, APIConnectionError, APIStatusError
from server.planning_core import PlanningError


def public_error(exc: Exception) -> str:
    unchanged = " Your trip is unchanged."
    if isinstance(exc, PlanningError):
        return str(exc)
    if isinstance(exc, AuthenticationError):
        return "Detour's AI connection needs to be reconfigured. Please contact the app owner to restore planning." + unchanged
    if isinstance(exc, PermissionDeniedError):
        return "Detour's AI service isn't available to this account. Please contact the app owner." + unchanged
    if isinstance(exc, RateLimitError):
        return "Detour's AI service is busy. Please wait a moment and try again." + unchanged
    if isinstance(exc, APIConnectionError):
        return "Detour couldn't reach its AI service. Please try again in a moment." + unchanged
    if isinstance(exc, APIStatusError) and exc.status_code >= 500:
        return "Detour's AI service is temporarily unavailable. Please try again shortly." + unchanged
    if isinstance(exc, APIStatusError):
        # 4xx provider errors are configuration problems (model, request size); name the
        # status and provider error type, never the body, which can echo request content.
        kind = (getattr(exc, "body", None) or {}).get("error", {}).get("type", "") if isinstance(getattr(exc, "body", None), dict) else ""
        return f"Planning could not complete (AI service error {exc.status_code}{' ' + kind if kind else ''}). Please try again." + unchanged
    return f"Planning could not complete ({type(exc).__name__}). Please try again." + unchanged
