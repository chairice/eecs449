"""Explicit authenticated RPC bridge for Jac 0.37.14.

The compiler's automatic bridge handles public endpoints only. Keep account
endpoints protected and use the runtime transport, which carries the session.
"""
import from "@jac/runtime" { __jacCallFunction }

async def:pub planner_list(active_trip_id: str = "") -> str { return str(await __jacCallFunction("planner_list", {"active_trip_id": active_trip_id})); }
async def:pub planner_get(trip_id: str) -> str { return str(await __jacCallFunction("planner_get", {"trip_id": trip_id})); }
async def:pub planner_import(state_json: str, token: str) -> str { return str(await __jacCallFunction("planner_import", {"state_json": state_json, "token": token})); }
async def:pub planner_start(trip_id: str, request_json: str) -> str { return str(await __jacCallFunction("planner_start", {"trip_id": trip_id, "request_json": request_json})); }
async def:pub planner_poll(trip_id: str, job_id: str) -> str { return str(await __jacCallFunction("planner_poll", {"trip_id": trip_id, "job_id": job_id})); }
async def:pub planner_stage(trip_id: str, job_id: str) -> str { return str(await __jacCallFunction("planner_stage", {"trip_id": trip_id, "job_id": job_id})); }
async def:pub planner_cancel(trip_id: str, job_id: str) -> str { return str(await __jacCallFunction("planner_cancel", {"trip_id": trip_id, "job_id": job_id})); }
async def:pub planner_reject(trip_id: str, proposal_id: str) -> str { return str(await __jacCallFunction("planner_reject", {"trip_id": trip_id, "proposal_id": proposal_id})); }
async def:pub planner_approve(trip_id: str, proposal_id: str, revision: int, command_id: str) -> str {
    return str(await __jacCallFunction("planner_approve", {"trip_id": trip_id, "proposal_id": proposal_id, "revision": revision, "command_id": command_id}));
}
async def:pub planner_upload(name: str, media: str, content: str) -> str { return str(await __jacCallFunction("planner_upload", {"name": name, "media": media, "content": content})); }
async def:pub planner_preferences -> str { return str(await __jacCallFunction("planner_preferences")); }
async def:pub planner_forget_preference(key: str) -> str { return str(await __jacCallFunction("planner_forget_preference", {"key": key})); }

async def:pub planner_undo(trip_id: str, revision: int, command_id: str) -> str { return str(await __jacCallFunction("planner_undo", {"trip_id": trip_id, "revision": revision, "command_id": command_id})); }
async def:pub planner_rename(trip_id: str, title: str, revision: int, command_id: str) -> str {
    return str(await __jacCallFunction("planner_rename", {"trip_id": trip_id, "title": title, "revision": revision, "command_id": command_id}));
}
async def:pub planner_delete(trip_id: str) -> str { return str(await __jacCallFunction("planner_delete", {"trip_id": trip_id})); }
async def:pub planner_restore(trip_id: str) -> str { return str(await __jacCallFunction("planner_restore", {"trip_id": trip_id})); }
async def:pub planner_deleted -> str { return str(await __jacCallFunction("planner_deleted")); }
async def:pub planner_weather(trip_id: str) -> str { return str(await __jacCallFunction("planner_weather", {"trip_id": trip_id})); }
