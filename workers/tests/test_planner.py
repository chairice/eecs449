from types import SimpleNamespace
import copy
import json
import pytest
from atlas_runtime.planner import plan
from server.planning_core import blank_trip, PlanningError
from server.planning_api import learn, forget_json
from atlas_runtime.travel_tools import check_schedule


class Block:
    type = "tool_use"
    name = "finish_plan"
    id = "tool_test"
    def __init__(self, value, name="finish_plan"): self.input = value; self.name = name
    def model_dump(self, **kwargs):
        return {"type": self.type, "name": self.name, "id": self.id, "input": self.input}


class Client:
    def __init__(self, responses):
        self.responses = iter(responses); self.calls = []; self.messages = self
    def create(self, **kwargs):
        self.calls.append(copy.deepcopy(kwargs))
        value = next(self.responses)
        block = Block(value[1], value[0]) if isinstance(value, tuple) else Block(value)
        return SimpleNamespace(content=[block], usage=SimpleNamespace(input_tokens=10, output_tokens=20))


def request():
    trip = blank_trip("trip_test")
    return {"tripId": trip["id"], "snapshot": trip, "message": "A work trip, logistics only", "attachments": [], "conversation": []}


def response(operations):
    return {"assistantMessage": "Here is a proposal.", "operations": operations, "workingContext": {"adults": 1},
            "summary": "A work trip", "nextDecision": {"question": "Where to?"}}


def test_schema_repair_retains_original_context_without_changing_accepted_state():
    value = request(); before = copy.deepcopy(value)
    client = Client([response([{"action": "not_an_operation"}]), response([{"action": "set_trip", "value": {"detail": "LOGISTICS", "intent": "BUSINESS"}}])])
    result = plan(value, "test", client=client)
    assert value == before
    assert result["proposed"]["detail"] == "LOGISTICS"
    assert len(client.calls) == 2
    repair = client.calls[1]["messages"][-1]["content"][0]
    assert repair["is_error"] and "correct the operations" in repair["content"]
    assert result["usage"] == {"inputTokens": 20, "outputTokens": 40}


def test_stopped_request_makes_no_model_call():
    client = Client([])
    with pytest.raises(PlanningError, match="stopped"):
        plan(request(), "test", client=client, running=lambda: False)
    assert client.calls == []


def test_forgetting_preference_blocks_relearning_from_old_or_later_automatic_updates():
    profile = learn({}, [{"key": "hiking", "value": "Easy trails"}], "job1")
    profile = json.loads(forget_json(json.dumps(profile), "hiking"))
    profile = learn(profile, [{"key": "hiking", "value": "Long hikes"}], "job2")
    assert "hiking" not in profile["values"] and "hiking" in profile["forgotten"]
    assert learn(profile, [], "job2") == profile


def test_schedule_checks_surface_overlap_and_do_not_claim_unsupported_verification():
    snapshot = {"days": [{"date": "2026-12-27", "items": [
        {"title": "First", "startTime": "10:00", "endTime": "12:00", "locked": False, "timingState": "CHECKED", "sourceRefs": []},
        {"title": "Second", "startTime": "11:00", "endTime": "13:00", "locked": False, "timingState": "PROVISIONAL", "sourceRefs": []}]}]}
    warnings = check_schedule(snapshot, set())
    assert snapshot["days"][0]["items"][0]["timingState"] == "PROVISIONAL"
    assert snapshot["days"][0]["items"][1]["timingState"] == "CONFLICT"
    assert "overlaps" in warnings[0]


def test_batched_proposal_publishes_only_unapproved_work_and_finishes_complete():
    value = request(); before = copy.deepcopy(value)
    client = Client([("stage_operations", {"operations": [{"action": "set_trip", "value": {"title": "Working draft"}}]}), response([])])
    previews = []
    result = plan(value, "test", client=client, publish=lambda snapshot: previews.append(copy.deepcopy(snapshot)))
    assert value == before
    assert previews[0]["title"] == "Working draft"
    assert result["proposed"]["title"] == "Working draft"
    assert len(result["operations"]) == 1


def test_incomplete_response_is_repaired_instead_of_returning_partial_plan():
    client = Client([{"assistantMessage": "Partial", "operations": []}, response([])])
    result = plan(request(), "test", client=client)
    assert result["assistantMessage"] == "Here is a proposal."
    assert len(client.calls) == 2


def test_open_research_components_cannot_be_silently_abandoned(monkeypatch):
    class CapturedBrowser:
        captures = {'source_test': {'captureId':'source_test','url':'https://provider.example/results','title':'Results','observedAt':1}}
        def close(self): pass
    monkeypatch.setattr('atlas_runtime.planner.ResearchBrowser', CapturedBrowser)
    components = [{'id':'outbound','query':{'category':'FLIGHT','origin':'DTW','destination':'SFO','departDate':'2026-11-22','adults':1,'childrenAges':[]},'status':'OPEN'}, {'id':'onward','query':{'category':'FLIGHT','origin':'SFO','destination':'XNA','departDate':'2026-11-25','adults':1,'childrenAges':[]},'status':'OPEN'}]
    resolved = [dict(component,status='BLOCKED',reason='Provider did not return search results',captureIds=['source_test']) for component in components]
    client = Client([('research_components',{'components':components}),response([]),('research_components',{'components':resolved}),response([])])
    result = plan(request(),'test',client=client)
    assert len(result['researchComponents']) == 2
    repair = client.calls[2]['messages'][-1]['content'][0]
    assert repair['is_error'] and 'OPEN component' in repair['content']


def test_requested_edit_authorization_and_decision_binding_survive_validation():
    final = response([{'action':'set_trip','value':{'title':'Requested title'}}])
    final['editAuthorization'] = {'source':'USER_REQUEST','confirmedDecisionId':'decision_7'}
    result = plan(request(),'test',client=Client([final]))
    assert result['editAuthorization'] == final['editAuthorization']


def test_agent_question_without_concrete_changes_is_repaired():
    incomplete = response([])
    incomplete.update(editAuthorization={'source':'AGENT_SUGGESTION'}, decision={'question':'Add a night?'})
    complete = response([{'action':'set_trip','value':{'title':'Longer stay'}}])
    complete.update(editAuthorization={'source':'AGENT_SUGGESTION'}, decision={'question':'Add a night?'})
    client = Client([incomplete,complete])
    result = plan(request(),'test',client=client)
    assert result['decision']['question'] == 'Add a night?'
    assert result['operations']
    assert 'remain pending' in client.calls[1]['messages'][-1]['content'][0]['content']


def test_old_browser_context_is_bounded_but_capture_ids_remain_rereadable():
    from atlas_runtime.planner import compact_browser_results
    messages = [{'role':'user','content':[{'type':'tool_result','tool_use_id':str(i),'content':json.dumps({'captureId':str(i),'url':'https://example.com','text':'source '*2000})}]} for i in range(8)]
    compact_browser_results(messages,keep=3)
    assert all(json.loads(message['content'][0]['content']).get('retainedCapture') for message in messages[:5])
    assert all(len(json.loads(message['content'][0]['content'])['text']) == 14000 for message in messages[5:])
    assert [json.loads(message['content'][0]['content'])['captureId'] for message in messages] == [str(i) for i in range(8)]


def test_signed_thinking_blocks_are_not_reused_after_page_context_compaction():
    class Thinking:
        type = 'thinking'
        def model_dump(self,**kwargs): return {'type':'thinking','thinking':'private','signature':'bound-to-old-prefix'}
    class ThinkingClient(Client):
        def create(self,**kwargs):
            value = super().create(**kwargs)
            value.content.insert(0,Thinking())
            return value
    client = ThinkingClient([('stage_operations',{'operations':[{'action':'set_trip','value':{'title':'New title'}}]}),response([])])
    plan(request(),'test',client=client)
    assert all(block.get('type') != 'thinking' for message in client.calls[1]['messages'] for block in message.get('content',[]) if isinstance(block,dict))


def test_bad_stay_candidates_cannot_erase_genuine_flight_options(monkeypatch):
    class CapturedBrowser:
        captures = {'source_test': {'captureId':'source_test','url':'https://provider.example/results','title':'Results','observedAt':1}}
        def close(self): pass
    monkeypatch.setattr('atlas_runtime.planner.ResearchBrowser', CapturedBrowser)
    flight = {'id':'real_flight','componentId':'flight','category':'FLIGHT','query':{'origin':'DTW','destination':'SFO','departDate':'2026-11-22','adults':1,'childrenAges':[]},'observedAt':1}
    monkeypatch.setattr('atlas_runtime.planner.verified_offers',lambda *args: ([copy.deepcopy(flight)],['Stay price did not match its capture']))
    searches = [
        {'id':'flight','query':dict(flight['query'],category='FLIGHT'),'status':'COMPLETE','captureIds':['source_test']},
        {'id':'stay','query':{'category':'HOTEL','location':'San Francisco','checkIn':'2026-11-22','checkOut':'2026-11-25','adults':1,'childrenAges':[],'rooms':1},'status':'COMPLETE','captureIds':['source_test']},
    ]
    final = response([])
    final.update(offers=[{'componentId':'flight'},{'componentId':'stay'}],assistantMessage='The hotel is $9999!')
    result = plan(request(),'test',client=Client([('research_components',{'components':searches}),final,final,final]))
    assert [offer['id'] for offer in result['offers']] == ['real_flight']
    assert '9999' not in result['assistantMessage'] and 'validation' not in result['assistantMessage']
    assert result['researchComponents'][0]['status'] == 'COMPLETE'
    assert result['researchComponents'][1]['status'] == 'INCOMPLETE'
    assert result['operations'] == []
