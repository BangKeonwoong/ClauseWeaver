# Mother Edit DnD Program Design

## Goals
- Implement the "mother" (parent clause) reparenting tool described in the spec.
- Provide a FastAPI backend that exposes tree data and supports reparent operations with validation.
- Provide a React frontend that displays a tree in textual slot order and allows permitted drag-and-drop reparenting.

## High-Level Architecture
```
repo
├── backend
│   ├── app.py           # FastAPI application entry point
│   ├── models.py        # Pydantic models and domain helpers
│   ├── storage.py       # Text-Fabric backed storage (BHSA clauses + overlay edges)
│   ├── services.py      # Business logic (validation, reparent operations)
│   └── tests
│       └── test_mother.py
├── frontend
│   ├── package.json     # Vite + React + TypeScript setup
│   ├── tsconfig.json
│   ├── vite.config.ts
│   ├── src
│   │   ├── main.tsx
│   │   ├── App.tsx
│   │   ├── api.ts
│   │   ├── hooks
│   │   │   └── useTree.ts
│   │   ├── components
│   │   │   ├── TreeView.tsx
│   │   │   ├── ClauseNode.tsx
│   │   │   └── DragLayer.tsx
│   │   └── types.ts
│   └── public
│       └── index.html
└── docs
    └── mother_edit_design.md
```

## Core Data Concepts
- **Node**: clause segment with `id`, `slotsStart` (textual order key), `label`, `containerId` (`"Book.Chapter.Verse"`), and cached verse metadata from BHSA.
- **Edge**: `mother` relation representing the parent clause (`from` child, `to` mother or `null`).
- **Overlay**: user edits stored separately from original data; the effective mother is the overlay value when present, otherwise the original.

## Backend Responsibilities
1. Serve the tree snapshot for a given scope via `GET /tree` (default UI supplies a verse/chapter scope to avoid loading all ~88k clauses).
2. Accept reparent requests (`POST /mother/reparent`, `POST /mother/rootify`, `POST /mother/reparent-batch`).
3. Validate operations:
   - Prevent self-parenting.
   - Prevent cycles by checking descendants under effective relationships.
   - Enforce container scoping (same verse by default).
   - Optional max depth enforcement (configurable, default disabled in demo).
4. Load BHSA clause nodes and the `mother` edge feature from Text-Fabric (`etcbc/bhsa/tf/2021` by default), while keeping user edits as overlay edges.
5. Maintain overlay storage and expose version metadata (timestamp-based).
6. Offer simple undo/redo stacks in memory (stretch goal, tracked but not persisted).

## Frontend Responsibilities
1. Fetch tree data for the active scope and keep `effectiveEdges`, `nodes`, and `edited` sets in state.
2. Render nodes in textual slot order using a simple tree layout (parents left, children to the right) while always respecting `slotsStart` ordering.
3. Provide drag-and-drop interactions that:
   - Highlight valid drop targets (same container, not descendant/self).
   - Allow optional rootify hotspots.
   - Call backend reparent endpoints and update state on success.
   - Display error toasts for invalid operations.
4. Provide a scope input (verse/chapter range) so users can focus on manageable subsets of the corpus.
5. Offer undo/redo buttons using the backend stack (if exposed) or client-side history.

## Libraries / Tooling
- Backend: FastAPI, Uvicorn (dev), Pydantic, Text-Fabric (`text-fabric`), pytest.
- Frontend: Vite, React, TypeScript, Zustand (state), `@dnd-kit/core` for drag-and-drop (lightweight).

## Testing Strategy
- Backend unit tests for `can_reparent` logic and API responses.
- Frontend: minimal due to time; rely on TypeScript types and manual verification instructions.

## Future Enhancements
- Persist overlays to disk or database.
- Implement authentication & multi-user sessions.
- Provide richer scope pickers (book dropdown, chapter navigation) and caching for large scopes.
