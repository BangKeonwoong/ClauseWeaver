import pytest
from fastapi.testclient import TestClient

from backend.app import app
from backend import storage as storage_module


client = TestClient(app)


@pytest.fixture(scope="module")
def storage_instance():
    storage_module._storage_instance = storage_module.MotherStorage()
    yield storage_module._storage_instance


@pytest.fixture(autouse=True)
def reset_storage(storage_instance):
    storage_instance.reset_overlays()
    yield


def test_get_tree_returns_nodes_and_edges():
    resp = client.get("/tree", params={"scope": "Gen.1.1-3"})
    assert resp.status_code == 200
    data = resp.json()
    node_ids = {node["id"] for node in data["nodes"]}
    assert {427559, 427560}.issubset(node_ids)
    assert all("slotsStart" in node for node in data["nodes"])
    assert all("inScope" in node for node in data["nodes"])
    assert all("kind" in node for node in data["nodes"])
    assert all("draggable" in node for node in data["nodes"])
    assert len(data["edges"]) >= 1


def test_reparent_within_container_succeeds():
    child = 427567
    new_mother = 427566
    resp = client.post("/mother/reparent", json={"child": child, "newMother": new_mother})
    assert resp.status_code == 200
    data = resp.json()
    assert data["edge"]["from"] == child
    assert data["edge"]["to"] == new_mother
    tree = client.get("/tree", params={"scope": "Gen.1.4"}).json()
    edge = next(edge for edge in tree["edges"] if edge["from"] == child)
    assert edge["to"] == new_mother
    assert edge["source"] == "original"


def test_reparent_rejects_descendant_even_if_same_container():
    resp = client.post("/mother/reparent", json={"child": 427566, "newMother": 427567})
    assert resp.status_code == 409
    assert resp.json()["reason"] == "MOTHER_ID_NOT_SMALLER"


def test_reparent_allows_cross_container_by_default():
    resp = client.post("/mother/reparent", json={"child": 427567, "newMother": 427560})
    assert resp.status_code == 200
    data = resp.json()
    assert data["edge"]["to"] == 427560


def test_reparent_rejects_larger_id():
    resp = client.post("/mother/reparent", json={"child": 427567, "newMother": 427568})
    assert resp.status_code == 409
    assert resp.json()["reason"] == "MOTHER_ID_NOT_SMALLER"


def test_tree_preserves_original_bhsa_relationship():
    resp = client.get("/tree", params={"scope": "Gen.1.18"})
    assert resp.status_code == 200
    data = resp.json()
    edges = {(edge["from"], edge["to"]) for edge in data["edges"] if edge["to"] is not None}
    assert (427619, 427618) in edges


def test_rootify_allows_null_parent():
    resp = client.post("/mother/rootify", json={"child": 427567})
    assert resp.status_code == 200
    assert resp.json()["edge"]["to"] is None
    tree = client.get("/tree", params={"scope": "Gen.1.4"}).json()
    edge = next(edge for edge in tree["edges"] if edge["from"] == 427567)
    assert edge["to"] is None


def test_batch_operation_rolls_back_on_failure():
    resp = client.post(
        "/mother/reparent-batch",
        json={
            "ops": [
                {"child": 427568, "newMother": 427567},
                {"child": 427566, "newMother": 427567},
            ]
        },
    )
    assert resp.status_code == 409
    tree = client.get("/tree", params={"scope": "Gen.1.4"}).json()
    edge_child = next(edge for edge in tree["edges"] if edge["from"] == 427568)
    assert edge_child["to"] == 427566
