from __future__ import annotations

import asyncio
import os
import signal
from typing import List, Optional

from fastapi import BackgroundTasks, Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .models import (
    BatchReparentRequest,
    EdgeDTO,
    EdgeSource,
    ErrorResponse,
    ReparentRequest,
    RootifyRequest,
    SuccessResponse,
    TreeResponse,
    NodeDTO,
    RelatedClauseDTO,
)
from .services import MotherError, MotherService
from .storage import MotherStorage, storage_dependency


async def _shutdown_app() -> None:
    await asyncio.sleep(0.2)
    os.kill(os.getpid(), signal.SIGINT)

app = FastAPI(title="Mother Reparenting Demo", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def service_dependency(storage: MotherStorage = Depends(storage_dependency)) -> MotherService:
    return MotherService(storage)


@app.get("/tree", response_model=TreeResponse)
def get_tree(
    scope: Optional[str] = None,
    svc: MotherService = Depends(service_dependency),
) -> TreeResponse:
    storage = svc.storage
    tree = storage.effective_tree(scope)
    overlay = storage.overlay_map()

    nodes: List[NodeDTO] = [
        NodeDTO(
            id=node.id,
            slots_start=node.slots_start,
            slots_end=node.slots_end,
            slot_count=node.slot_count,
            label=node.label,
            container_id=node.container_id,
            inScope=node.id in tree.in_scope_ids,
            kind=node.kind,
            draggable=node.kind == "clause",
            typ=node.typ,
            rela=node.rela,
            code=node.code,
            txt=node.txt,
            domain=node.domain,
            instruction=node.instruction,
            original_mother=node.original_mother,
            coreFunctions=list(node.core_functions),
            reference=node.reference,
        )
        for node in tree.nodes.values()
    ]

    # ensure nodes sorted by textual order
    nodes.sort(key=lambda dto: dto.slotsStart)
    slot_map = {dto.id: dto.slotsStart for dto in nodes}

    edges: List[EdgeDTO] = []
    for child_id, mother_id in tree.mothers.items():
        source = EdgeSource.user if child_id in overlay else EdgeSource.original
        edge = EdgeDTO(from_id=child_id, to=mother_id, source=source)
        edges.append(edge)

    edges.sort(key=lambda edge: slot_map.get(edge.from_id, edge.from_id))

    return TreeResponse(nodes=nodes, edges=edges, scope=scope, version=storage.version)


@app.post("/mother/reparent", response_model=SuccessResponse, responses={409: {"model": ErrorResponse}})
def reparent(
    payload: ReparentRequest,
    svc: MotherService = Depends(service_dependency),
) -> SuccessResponse:
    try:
        new_mother = svc.reparent(payload.child, payload.newMother)
    except MotherError as exc:
        return JSONResponse(
            status_code=exc.status_code,
            content={"ok": False, "reason": exc.reason},
        )
    storage = svc.storage
    overlay = storage.overlay_map()
    source = EdgeSource.user if payload.child in overlay else EdgeSource.original
    edge = EdgeDTO(from_id=payload.child, to=new_mother, source=source)
    return SuccessResponse(edge=edge, version=storage.version)


@app.post("/mother/rootify", response_model=SuccessResponse, responses={405: {"model": ErrorResponse}})
def rootify(
    payload: RootifyRequest,
    svc: MotherService = Depends(service_dependency),
) -> SuccessResponse:
    try:
        svc.rootify(payload.child)
    except MotherError as exc:
        return JSONResponse(
            status_code=exc.status_code,
            content={"ok": False, "reason": exc.reason},
        )
    storage = svc.storage
    source = EdgeSource.user
    edge = EdgeDTO(from_id=payload.child, to=None, source=source)
    return SuccessResponse(edge=edge, version=storage.version)


@app.post(
    "/mother/reparent-batch",
    response_model=TreeResponse,
    responses={409: {"model": ErrorResponse}},
)
def reparent_batch(
    payload: BatchReparentRequest,
    svc: MotherService = Depends(service_dependency),
) -> TreeResponse:
    operations = [
        (op.child, op.newMother)
        for op in payload.ops
    ]
    try:
        svc.reparent_batch(operations)
    except MotherError as exc:
        return JSONResponse(
            status_code=exc.status_code,
            content={"ok": False, "reason": exc.reason},
        )
    storage = svc.storage
    tree = storage.effective_tree()
    overlay = storage.overlay_map()

    nodes: List[NodeDTO] = [
        NodeDTO(
            id=node.id,
            slots_start=node.slots_start,
            slots_end=node.slots_end,
            slot_count=node.slot_count,
            label=node.label,
            container_id=node.container_id,
            inScope=node.id in tree.in_scope_ids,
            kind=node.kind,
            draggable=node.kind == "clause",
            typ=node.typ,
            rela=node.rela,
            code=node.code,
            txt=node.txt,
            domain=node.domain,
            instruction=node.instruction,
            original_mother=node.original_mother,
            coreFunctions=list(node.core_functions),
            reference=node.reference,
        )
        for node in tree.nodes.values()
    ]
    nodes.sort(key=lambda dto: dto.slotsStart)
    slot_map = {dto.id: dto.slotsStart for dto in nodes}

    edges: List[EdgeDTO] = []
    for child_id, mother_id in tree.mothers.items():
        source = EdgeSource.user if child_id in overlay else EdgeSource.original
        edges.append(EdgeDTO(from_id=child_id, to=mother_id, source=source))

    edges.sort(key=lambda edge: slot_map.get(edge.from_id, edge.from_id))

    return TreeResponse(nodes=nodes, edges=edges, scope=None, version=storage.version)


@app.post("/mother/undo", response_model=SuccessResponse, responses={409: {"model": ErrorResponse}})
def undo(svc: MotherService = Depends(service_dependency)) -> SuccessResponse:
    result = svc.storage.undo()
    if result is None:
        return JSONResponse(
            status_code=409,
            content={"ok": False, "reason": "NO_HISTORY"},
        )
    child, mother = result
    overlay = svc.storage.overlay_map()
    source = EdgeSource.user if child in overlay else EdgeSource.original
    return SuccessResponse(edge=EdgeDTO(from_id=child, to=mother, source=source), version=svc.storage.version)


@app.post("/mother/redo", response_model=SuccessResponse, responses={409: {"model": ErrorResponse}})
def redo(svc: MotherService = Depends(service_dependency)) -> SuccessResponse:
    result = svc.storage.redo()
    if result is None:
        return JSONResponse(
            status_code=409,
            content={"ok": False, "reason": "NO_HISTORY"},
        )
    child, mother = result
    overlay = svc.storage.overlay_map()
    source = EdgeSource.user if child in overlay else EdgeSource.original
    return SuccessResponse(edge=EdgeDTO(from_id=child, to=mother, source=source), version=svc.storage.version)


@app.post("/shutdown")
async def shutdown(background_tasks: BackgroundTasks) -> dict[str, bool | str]:
    background_tasks.add_task(_shutdown_app)
    return {"ok": True, "message": "SERVER_SHUTTING_DOWN"}
    node_lookup = {dto.id: dto for dto in nodes}
    for child_id, mother_id in tree.mothers.items():
        if mother_id is None:
            continue
        parent_dto = node_lookup.get(mother_id)
        child_node = tree.nodes.get(child_id)
        if not parent_dto or not child_node:
            continue
        parent_dto.children.append(
            RelatedClauseDTO(
                id=child_id,
                typ=child_node.typ,
                rela=child_node.rela,
                code=child_node.code,
            )
        )

    for dto in nodes:
        if dto.children:
            dto.children.sort(key=lambda child: tree.nodes[child.id].slots_start)
    node_lookup = {dto.id: dto for dto in nodes}
    for child_id, mother_id in tree.mothers.items():
        if mother_id is None:
            continue
        parent_dto = node_lookup.get(mother_id)
        child_node = tree.nodes.get(child_id)
        if not parent_dto or not child_node:
            continue
        parent_dto.children.append(
            RelatedClauseDTO(
                id=child_id,
                typ=child_node.typ,
                rela=child_node.rela,
                code=child_node.code,
            )
        )

    for dto in nodes:
        if dto.children:
            dto.children.sort(key=lambda child: tree.nodes[child.id].slots_start)
