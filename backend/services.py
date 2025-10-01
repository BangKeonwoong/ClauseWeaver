from __future__ import annotations

from typing import Optional, Set

from fastapi import status

from .models import ClauseNode, ConfigOptions
from .storage import MotherStorage


class MotherError(Exception):
    def __init__(self, reason: str, status_code: int = status.HTTP_409_CONFLICT) -> None:
        super().__init__(reason)
        self.reason = reason
        self.status_code = status_code


class MotherService:
    def __init__(self, storage: MotherStorage) -> None:
        self.storage = storage
        self.config: ConfigOptions = storage.config

    # ---------- Validation helpers ----------
    def _require_node(self, node_id: int):
        node = self.storage.get_node(node_id)
        if node is None:
            raise MotherError("NODE_NOT_FOUND", status.HTTP_404_NOT_FOUND)
        return node

    def _assert_scope(self, child: ClauseNode, mother: ClauseNode) -> None:
        if self.config.scope_container and child.container_id != mother.container_id:
            raise MotherError("CONTAINER_MISMATCH")

    def _descendants_of(self, node_id: int) -> Set[int]:
        descendants: Set[int] = set()
        children_map = self.storage.build_children_map()
        stack = [node_id]
        while stack:
            current = stack.pop()
            for child in children_map.get(current, []):
                if child in descendants:
                    continue
                descendants.add(child)
                stack.append(child)
        return descendants

    def _assert_cycle_free(self, child_id: int, new_mother_id: int) -> None:
        if child_id == new_mother_id:
            raise MotherError("SAME_NODE")
        descendants = self._descendants_of(child_id)
        if new_mother_id in descendants:
            raise MotherError("CYCLE")

    def _assert_depth(self, child_id: int, new_mother_id: Optional[int]) -> None:
        max_depth = self.config.max_depth
        if max_depth is None:
            return
        depth = 0
        current = new_mother_id
        while current is not None:
            depth += 1
            if depth > max_depth:
                raise MotherError("DEPTH_LIMIT")
            current = self.storage.get_effective_mother(current)
        # plus child itself
        if depth + 1 > max_depth:
            raise MotherError("DEPTH_LIMIT")

    # ---------- Public operations ----------
    def reparent(self, child_id: int, new_mother_id: int) -> Optional[int]:
        child = self._require_node(child_id)
        mother = self._require_node(new_mother_id)
        if mother.kind != "clause":
            raise MotherError("MOTHER_NOT_CLAUSE")
        if new_mother_id >= child_id:
            raise MotherError("MOTHER_ID_NOT_SMALLER")
        self._assert_scope(child, mother)
        self._assert_cycle_free(child_id, new_mother_id)
        self._assert_depth(child_id, new_mother_id)
        self.storage.set_mother(child_id, new_mother_id)
        return new_mother_id

    def rootify(self, child_id: int) -> None:
        self._require_node(child_id)
        if not self.config.allow_rootify:
            raise MotherError("ROOTIFY_DISABLED", status.HTTP_405_METHOD_NOT_ALLOWED)
        self._assert_depth(child_id, None)
        self.storage.set_mother(child_id, None)

    def reparent_batch(self, operations: list[tuple[int, Optional[int]]]) -> None:
        # Use snapshot of mothers to ensure atomic application
        snapshot = self.storage.snapshot_state()
        try:
            for child_id, new_mother_id in operations:
                if new_mother_id is None:
                    self.rootify(child_id)
                else:
                    self.reparent(child_id, new_mother_id)
        except MotherError:
            self.storage.restore_state(snapshot)
            raise
