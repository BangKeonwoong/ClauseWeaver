from __future__ import annotations

from datetime import datetime, timezone
import os
from typing import Dict, List, Optional, Tuple, Set

from tf.fabric import Fabric

from fastapi import Depends

from .models import ClauseNode, ConfigOptions, EffectiveTree


class MotherStorage:
    """In-memory storage for clause nodes and user mother edits."""

    def __init__(self, config: Optional[ConfigOptions] = None) -> None:
        self.config = config or ConfigOptions()
        self._nodes: Dict[int, ClauseNode] = {}
        self._original_mother: Dict[int, Optional[int]] = {}
        self._overlay_mother: Dict[int, Optional[int]] = {}
        self._undo_stack: List[Tuple[int, Optional[int], Optional[int]]] = []
        self._redo_stack: List[Tuple[int, Optional[int], Optional[int]]] = []
        self._version = self._timestamp()
        self._book_names: List[str] = []
        self._book_normalized: Dict[str, str] = {}
        self._all_nodes: List[ClauseNode] = []
        self._tf_api = None
        self._fabric = None
        self._available_features: Set[str] = set()
        self._load_text_fabric_data()

    @staticmethod
    def _timestamp() -> str:
        return datetime.now(timezone.utc).isoformat()

    def _load_text_fabric_data(self) -> None:
        tf_location = self._resolve_tf_location()
        module_name = self._determine_module(tf_location, self.config.tf_module)
        self._fabric = Fabric(locations=tf_location, modules=[module_name])
        features = (
            "g_cons",
            "mother",
            "otype",
            "book",
            "chapter",
            "verse",
            "typ",
            "rela",
            "code",
            "txt",
            "domain",
            "instruction",
            "function",
        )
        optional_features = (
            "g_word_utf8",
            "g_vocal_utf8",
            "g_word_utf8a",
            "g_vocal",
        )

        module_path = os.path.normpath(os.path.join(tf_location, module_name))
        available_optionals = []
        for feature_name in optional_features:
            for ext in (".tf", ".tfx", ".tf.gz"):
                candidate_path = os.path.join(module_path, f"{feature_name}{ext}")
                if os.path.exists(candidate_path):
                    available_optionals.append(feature_name)
                    break

        feature_spec = " ".join(list(features) + available_optionals)
        print(f"[TF] Module path: {module_path}")
        print(f"[TF] Optional feature files found: {available_optionals}")
        print(f"[TF] Loading features: {feature_spec}")
        api = self._fabric.load(feature_spec, silent="auto")

        if not api:
            raise RuntimeError("Failed to load Text-Fabric data. Check tf_location and module settings.")

        self._tf_api = api
        self._available_features = set(features).union(available_optionals)
        E = api.E
        L = api.L
        T = api.T

        book_nodes = list(F.otype.s("book"))
        self._book_names = [T.bookName(n) for n in book_nodes]
        self._build_book_lookup()

        label_limit = max(1, self.config.label_max_words)

        clause_nodes: List[ClauseNode] = []

        verse_counters: Dict[Tuple[str, int, int], int] = {}

        for node in F.otype.s("clause"):
            book, chapter, verse = T.sectionFromNode(node)
            label = self._make_clause_label(node, label_limit)
            container_id = f"{book.replace('_', ' ')}.{chapter}.{verse}"
            key = (book, chapter, verse)
            counter = verse_counters.get(key, 0)
            suffix = chr(ord('a') + counter)
            verse_counters[key] = counter + 1
            ref = f"{book.replace('_', ' ').title()} {chapter}:{verse}{suffix}"
            mother = self._resolve_clause_mother(node)
            first_slot = self._first_slot(node)
            last_slot = self._last_slot(node)
            typ = F.typ.v(node)
            rela = F.rela.v(node)
            code = F.code.v(node)
            txt = F.txt.v(node)
            domain = F.domain.v(node)
            instruction = self._clause_instruction(node)
            core_functions = self._core_functions(node)
            clause = ClauseNode(
                id=node,
                slots_start=first_slot,
                slots_end=last_slot,
                slot_count=max(1, last_slot - first_slot + 1) if last_slot else 0,
                label=label,
                container_id=container_id,
                original_mother=mother,
                book=book,
                chapter=chapter,
                verse=verse,
                typ=typ or None,
                rela=rela or None,
                code=code or None,
                txt=txt or None,
                domain=domain or None,
                instruction=instruction,
                core_functions=core_functions,
                reference=ref,
            )
            self._nodes[node] = clause
            self._original_mother[node] = mother
            clause_nodes.append(clause)

        clause_nodes.sort(key=lambda c: c.slots_start)
        self._all_nodes = clause_nodes

    def _resolve_tf_location(self) -> str:
        if self.config.tf_location:
            return os.path.expanduser(self.config.tf_location)
        env_location = os.getenv("TF_DATA_LOCATION") or os.getenv("TEXT_FABRIC_DATA")
        if env_location:
            return os.path.expanduser(env_location)
        return os.path.expanduser("~/text-fabric-data")

    def _determine_module(self, location: str, module: str) -> str:
        module = module.strip()
        if not module:
            raise ValueError("tf_module cannot be empty")

        candidates = [module]
        if "/" in module:
            parts = module.split("/")
            # include suffixes (drop leading segments)
            for idx in range(1, len(parts)):
                tail = "/".join(parts[idx:])
                if tail and tail not in candidates:
                    candidates.append(tail)
            # include prefixes (drop trailing segments)
            for idx in range(len(parts) - 1, 0, -1):
                prefix = "/".join(parts[:idx])
                if prefix and prefix not in candidates:
                    candidates.append(prefix)

        for cand in candidates:
            candidate_path = os.path.join(location, cand)
            if os.path.exists(candidate_path):
                return cand

        return module

    def _build_book_lookup(self) -> None:
        lookup: Dict[str, str] = {}
        for book in self._book_names:
            normalized = self._normalize_book_key(book)
            lookup[normalized] = book
            lookup[book.lower()] = book
            lookup[book.replace("_", " ").lower()] = book
            lookup[book.replace("_", "").lower()] = book
        self._book_normalized = lookup

    def _normalize_book_key(self, value: str) -> str:
        return value.replace("_", "").replace(" ", "").replace(".", "").lower()

    def _resolve_book_name(self, token: str) -> Optional[str]:
        key = self._normalize_book_key(token)
        matches = [book for norm, book in self._book_normalized.items() if norm.startswith(key)]
        if not matches:
            return None
        # Prefer exact match
        exact = [book for book in matches if self._normalize_book_key(book) == key]
        if exact:
            return exact[0]
        # Remove duplicates while preserving order
        seen = set()
        ordered: List[str] = []
        for book in matches:
            if book not in seen:
                ordered.append(book)
                seen.add(book)
        if len(ordered) == 1:
            return ordered[0]
        return None

    def _make_clause_label(self, node: int, limit: int) -> str:
        assert self._tf_api is not None
        F = self._tf_api.F
        L = self._tf_api.L
        words = []
        lexical_priority = ("g_word_utf8", "g_vocal_utf8", "g_word_utf8a", "g_vocal")
        for word_node in L.d(node, "word")[:limit]:
            lex = ""
            for feature_name in lexical_priority:
                if feature_name in self._available_features:
                    feature = getattr(F, feature_name, None)
                    if feature is None:
                        continue
                    value = feature.v(word_node)
                    if value:
                        lex = value
                        break
            if not lex and "g_cons" in self._available_features:
                lex = F.g_cons.v(word_node)
            words.append(lex)
        label = " ".join(word for word in words if word)
        total_words = len(L.d(node, "word"))
        if total_words > limit:
            label = f"{label} …"
        return label

    def _first_slot(self, node: int) -> int:
        assert self._tf_api is not None
        L = self._tf_api.L
        slots = L.d(node, "word")
        return slots[0] if slots else node

    def _last_slot(self, node: int) -> int:
        assert self._tf_api is not None
        L = self._tf_api.L
        slots = L.d(node, "word")
        if slots:
            return slots[-1]
        return node

    def _clause_instruction(self, clause_id: int) -> Optional[str]:
        assert self._tf_api is not None
        F = self._tf_api.F
        L = self._tf_api.L
        for clause_atom in L.d(clause_id, "clause_atom"):
            instr = F.instruction.v(clause_atom)
            if instr:
                return instr
        return None

    def _core_functions(self, clause_id: int) -> tuple[str, ...]:
        assert self._tf_api is not None
        F = self._tf_api.F
        L = self._tf_api.L
        priority = [
            "Pred",
            "Subj",
            "Objc",
            "PreC",
            "Cmpl",
            "Adju",
            "Attr",
        ]
        seen: Dict[str, None] = {}
        for phrase in L.d(clause_id, "phrase"):
            func = F.function.v(phrase)
            if func:
                seen.setdefault(func, None)
        ordered = [func for func in priority if func in seen]
        remainder = [func for func in seen.keys() if func not in priority]
        return tuple(ordered + remainder[:5])

    def _resolve_clause_mother(self, clause_id: int) -> Optional[int]:
        assert self._tf_api is not None
        E = self._tf_api.E
        F = self._tf_api.F
        L = self._tf_api.L

        visited: Set[int] = set()
        stack: List[int] = [clause_id]

        clause_atoms = L.d(clause_id, "clause_atom")
        stack.extend(clause_atoms)

        while stack:
            node = stack.pop()
            mother_tuple = E.mother.f(node)
            if not mother_tuple:
                continue
            mother = mother_tuple[0]
            if mother in visited:
                continue
            visited.add(mother)
            otype = F.otype.v(mother)
            if otype == "clause" and mother != clause_id:
                return mother
            clause_owner = L.u(mother, "clause")
            if clause_owner:
                parent_clause = clause_owner[0]
                if parent_clause != clause_id:
                    return parent_clause
            stack.append(mother)

        return None

    def _parse_scope(self, scope: str) -> Tuple[Optional[str], Optional[int], Optional[int], Optional[int]]:
        scope = scope.strip()
        if not scope:
            raise ValueError("empty scope")
        parts = scope.split(".")
        book_token = parts[0]
        book = self._resolve_book_name(book_token)
        if book is None:
            raise ValueError(f"unknown book: {book_token}")

        chapter: Optional[int] = None
        verse_start: Optional[int] = None
        verse_end: Optional[int] = None

        if len(parts) >= 2 and parts[1]:
            try:
                chapter = int(parts[1])
            except ValueError as exc:
                raise ValueError("invalid chapter") from exc

        if len(parts) >= 3 and parts[2]:
            verse_part = parts[2]
            if "-" in verse_part:
                start_str, end_str = verse_part.split("-", 1)
                try:
                    verse_start = int(start_str)
                    verse_end = int(end_str)
                except ValueError as exc:
                    raise ValueError("invalid verse range") from exc
                if verse_end < verse_start:
                    raise ValueError("invalid verse range ordering")
            else:
                try:
                    verse_start = int(verse_part)
                    verse_end = verse_start
                except ValueError as exc:
                    raise ValueError("invalid verse") from exc

        return book, chapter, verse_start, verse_end

    # ---------- Query helpers ----------
    def get_node(self, node_id: int) -> Optional[ClauseNode]:
        return self._nodes.get(node_id)

    def _filter_scope_nodes(self, scope: str) -> List[ClauseNode]:
        try:
            book, chapter, verse_start, verse_end = self._parse_scope(scope)
        except ValueError:
            return []

        filtered: List[ClauseNode] = []
        for node in self._all_nodes:
            if book and node.book != book:
                continue
            if chapter is not None and node.chapter != chapter:
                continue
            if verse_start is not None:
                if verse_end is not None:
                    if not (verse_start <= node.verse <= verse_end):
                        continue
                else:
                    if node.verse != verse_start:
                        continue
            filtered.append(node)
        return filtered

    def _effective_mothers_all(self) -> Dict[int, Optional[int]]:
        return {node_id: self.get_effective_mother(node_id) for node_id in self._nodes}

    def _children_map_all(self, mothers: Dict[int, Optional[int]]) -> Dict[int, List[int]]:
        children: Dict[int, List[int]] = {}
        for child, mother in mothers.items():
            if mother is None:
                continue
            children.setdefault(mother, []).append(child)
        for child_list in children.values():
            child_list.sort(key=lambda cid: self._nodes[cid].slots_start)
        return children

    def _scoped_nodes(self, scope: Optional[str]) -> tuple[List[ClauseNode], Set[int]]:
        if not scope:
            nodes = list(self._all_nodes)
            return nodes, {node.id for node in nodes}

        filtered = self._filter_scope_nodes(scope)
        if not filtered:
            return [], set()

        mothers_all = self._effective_mothers_all()
        children_all = self._children_map_all(mothers_all)

        nodes_map: Dict[int, ClauseNode] = {node.id: node for node in filtered}
        in_scope_ids: Set[int] = set(nodes_map.keys())

        queue: List[int] = list(nodes_map.keys())
        visited: Set[int] = set(queue)

        while queue:
            current = queue.pop()
            mother = mothers_all.get(current)
            if mother is None:
                continue
            if mother not in nodes_map:
                mother_node = self._nodes.get(mother)
                if mother_node is not None:
                    nodes_map[mother] = mother_node
                    if mother not in visited:
                        visited.add(mother)
                        queue.append(mother)

        snapshot_ids = list(nodes_map.keys())
        for node_id in snapshot_ids:
            mother = mothers_all.get(node_id)
            if mother is None:
                continue
            for sibling in children_all.get(mother, []):
                if sibling not in nodes_map:
                    nodes_map[sibling] = self._nodes[sibling]

        nodes = list(nodes_map.values())
        nodes.sort(key=lambda c: c.slots_start)
        return nodes, in_scope_ids

    def get_nodes(self, scope: Optional[str] = None) -> List[ClauseNode]:
        nodes, _ = self._scoped_nodes(scope)
        return nodes

    def get_effective_mother(self, node_id: int) -> Optional[int]:
        if node_id in self._overlay_mother:
            return self._overlay_mother[node_id]
        return self._original_mother.get(node_id)

    def effective_mothers(self, scope: Optional[str] = None) -> Dict[int, Optional[int]]:
        result: Dict[int, Optional[int]] = {}
        nodes, _ = self._scoped_nodes(scope)
        for node in nodes:
            result[node.id] = self.get_effective_mother(node.id)
        return result

    def build_children_map(self, scope: Optional[str] = None) -> Dict[int, List[int]]:
        children_map: Dict[int, List[int]] = {}
        for child, mother in self.effective_mothers(scope).items():
            if mother is None:
                continue
            children_map.setdefault(mother, []).append(child)
        for cid, child_list in children_map.items():
            child_list.sort(key=lambda child_id: self._nodes[child_id].slots_start)
        return children_map

    def effective_tree(self, scope: Optional[str] = None) -> EffectiveTree:
        scoped_nodes, in_scope_ids = self._scoped_nodes(scope)
        nodes = {node.id: node for node in scoped_nodes}
        mothers = self.effective_mothers(scope)
        return EffectiveTree(nodes=nodes, mothers=mothers, in_scope_ids=in_scope_ids)

    def overlay_map(self) -> Dict[int, Optional[int]]:
        return dict(self._overlay_mother)

    # ---------- Mutation helpers ----------
    def set_mother(self, child: int, new_mother: Optional[int]) -> None:
        prev = self.get_effective_mother(child)
        if new_mother == self._original_mother.get(child):
            # Remove overlay if returning to original
            self._overlay_mother.pop(child, None)
        else:
            self._overlay_mother[child] = new_mother
        self._push_history(child, prev, new_mother)
        self._version = self._timestamp()

    def _push_history(self, child: int, prev: Optional[int], new: Optional[int]) -> None:
        self._undo_stack.append((child, prev, new))
        self._redo_stack.clear()

    def undo(self) -> Optional[Tuple[int, Optional[int]]]:
        if not self._undo_stack:
            return None
        child, prev, new = self._undo_stack.pop()
        self._apply_history(child, prev)
        self._redo_stack.append((child, prev, new))
        return child, prev

    def redo(self) -> Optional[Tuple[int, Optional[int]]]:
        if not self._redo_stack:
            return None
        child, prev, new = self._redo_stack.pop()
        self._apply_history(child, new)
        self._undo_stack.append((child, prev, new))
        return child, new

    def _apply_history(self, child: int, mother: Optional[int]) -> None:
        if mother == self._original_mother.get(child):
            self._overlay_mother.pop(child, None)
        else:
            self._overlay_mother[child] = mother
        self._version = self._timestamp()

    @property
    def version(self) -> str:
        return self._version

    # ---------- Snapshot helpers (for batch & undo/redo) ----------
    def snapshot_state(self) -> Tuple[
        Dict[int, Optional[int]],
        List[Tuple[int, Optional[int], Optional[int]]],
        List[Tuple[int, Optional[int], Optional[int]]],
        str,
    ]:
        return (
            dict(self._overlay_mother),
            list(self._undo_stack),
            list(self._redo_stack),
            self._version,
        )

    def restore_state(
        self,
        snapshot: Tuple[
            Dict[int, Optional[int]],
            List[Tuple[int, Optional[int], Optional[int]]],
            List[Tuple[int, Optional[int], Optional[int]]],
            str,
        ],
    ) -> None:
        overlay, undo_stack, redo_stack, version = snapshot
        self._overlay_mother = overlay
        self._undo_stack = undo_stack
        self._redo_stack = redo_stack
        self._version = version

    def reset_overlays(self) -> None:
        self._overlay_mother.clear()
        self._undo_stack.clear()
        self._redo_stack.clear()
        self._version = self._timestamp()


_storage_instance: Optional[MotherStorage] = None


def get_storage() -> MotherStorage:
    global _storage_instance
    if _storage_instance is None:
        _storage_instance = MotherStorage()
    return _storage_instance


def storage_dependency(storage: MotherStorage = Depends(get_storage)) -> MotherStorage:
    return storage
