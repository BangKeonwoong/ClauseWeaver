from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Set

from pydantic import AliasChoices, BaseModel, Field
from pydantic.config import ConfigDict


@dataclass(slots=True)
class ClauseNode:
    """Internal representation of a clause node."""

    id: int
    slots_start: int
    label: str
    container_id: str
    original_mother: Optional[int]
    book: str
    chapter: int
    verse: int
    kind: str = "clause"
    typ: Optional[str] = None
    rela: Optional[str] = None
    code: Optional[str] = None
    txt: Optional[str] = None
    domain: Optional[str] = None
    instruction: Optional[str] = None
    slots_end: int = 0
    slot_count: int = 0
    core_functions: tuple[str, ...] = ()
    reference: str = ""


class EdgeSource(str, Enum):
    original = "original"
    user = "user"


class NodeDTO(BaseModel):
    id: int
    slotsStart: int = Field(validation_alias=AliasChoices("slots_start", "slotsStart"))
    slotsEnd: int = Field(validation_alias=AliasChoices("slots_end", "slotsEnd"))
    slotCount: int = Field(validation_alias=AliasChoices("slot_count", "slotCount"))
    label: str
    containerId: str = Field(validation_alias=AliasChoices("container_id", "containerId"))
    inScope: bool = True
    kind: str
    draggable: bool
    typ: Optional[str] = None
    rela: Optional[str] = None
    code: Optional[str] = None
    txt: Optional[str] = None
    domain: Optional[str] = None
    instruction: Optional[str] = None
    originalMother: Optional[int] = Field(default=None, validation_alias=AliasChoices("original_mother", "originalMother"))
    coreFunctions: List[str] = Field(default_factory=list)
    children: List["RelatedClauseDTO"] = Field(default_factory=list)
    reference: str

    model_config = ConfigDict(populate_by_name=True)


class RelatedClauseDTO(BaseModel):
    id: int
    typ: Optional[str] = None
    rela: Optional[str] = None
    code: Optional[str] = None


class EdgeDTO(BaseModel):
    from_id: int = Field(alias="from")
    to: Optional[int]
    source: EdgeSource

    class Config:
        populate_by_name = True


class TreeResponse(BaseModel):
    nodes: List[NodeDTO]
    edges: List[EdgeDTO]
    scope: Optional[str] = None
    version: str


class ReparentRequest(BaseModel):
    child: int
    newMother: int
    scope: Optional[str] = None


class RootifyRequest(BaseModel):
    child: int


class BatchOperation(BaseModel):
    child: int
    newMother: Optional[int]


class BatchReparentRequest(BaseModel):
    ops: List[BatchOperation]


class ErrorResponse(BaseModel):
    ok: bool = False
    reason: str


class SuccessResponse(BaseModel):
    ok: bool = True
    edge: EdgeDTO
    version: str


class ConfigOptions(BaseModel):
    scope_container: Optional[str] = None
    allow_rootify: bool = True
    max_depth: Optional[int] = None
    tf_location: Optional[str] = None
    tf_module: str = "etcbc/bhsa/tf/2021"
    label_max_words: int = 6


class EffectiveTree(BaseModel):
    nodes: Dict[int, ClauseNode]
    mothers: Dict[int, Optional[int]]
    in_scope_ids: Set[int]

    class Config:
        arbitrary_types_allowed = True


NodeDTO.model_rebuild()
