import { useCallback, useEffect, useMemo, useState } from "react";
import { fetchTree, redo, reparent, rootify, undo } from "../api";
import type { ClauseNodeDTO, DropTargets, EdgeDTO } from "../types";

export interface RenderNode {
  node: ClauseNodeDTO;
  depth: number;
  mother: number | null;
  isEdited: boolean;
}

export interface TreeHook {
  loading: boolean;
  mutating: boolean;
  error: string | null;
  renderTree: RenderNode[];
  orderedNodes: ClauseNodeDTO[];
  nodesById: Map<number, ClauseNodeDTO>;
  mothers: Map<number, number | null>;
  edited: Set<number>;
  refresh: () => Promise<void>;
  reparentNode: (child: number, newMother: number) => Promise<void>;
  rootifyNode: (child: number) => Promise<void>;
  undoLast: () => Promise<void>;
  redoLast: () => Promise<void>;
  computeDropTargets: (child: number) => DropTargets;
  clearError: () => void;
  reportError: (message: string) => void;
}

const REFETCH_DELAY = 150;

function buildEdgeMap(edges: EdgeDTO[]): Map<number, number | null> {
  const map = new Map<number, number | null>();
  edges.forEach((edge) => {
    map.set(edge.from, edge.to ?? null);
  });
  return map;
}

function buildChildrenMap(mothers: Map<number, number | null>): Map<number, number[]> {
  const children = new Map<number, number[]>();
  mothers.forEach((mother, child) => {
    if (mother === null || mother === undefined) {
      return;
    }
    if (!children.has(mother)) {
      children.set(mother, []);
    }
    children.get(mother)!.push(child);
  });
  return children;
}

function collectDescendants(
  root: number,
  childrenMap: Map<number, number[]>
): Set<number> {
  const visited = new Set<number>();
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop()!;
    const children = childrenMap.get(current) ?? [];
    for (const child of children) {
      if (!visited.has(child)) {
        visited.add(child);
        stack.push(child);
      }
    }
  }
  return visited;
}

function buildRenderTree(
  nodes: ClauseNodeDTO[],
  mothers: Map<number, number | null>,
  edited: Set<number>
): RenderNode[] {
  const nodesById = new Map(nodes.map((node) => [node.id, node]));

  const computeDepth = (id: number): number => {
    let depth = 0;
    let current = mothers.get(id) ?? null;
    const seen = new Set<number>();
    while (current != null && nodesById.has(current) && !seen.has(current)) {
      depth += 1;
      seen.add(current);
      current = mothers.get(current) ?? null;
    }
    return depth;
  };

  return nodes.map((node) => ({
    node,
    depth: computeDepth(node.id),
    mother: mothers.get(node.id) ?? null,
    isEdited: edited.has(node.id),
  }));
}

export function useTree(scope?: string | null): TreeHook {
  const [loading, setLoading] = useState(false);
  const [mutating, setMutating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nodes, setNodes] = useState<ClauseNodeDTO[]>([]);
  const [mothers, setMothers] = useState<Map<number, number | null>>(new Map());
  const [edited, setEdited] = useState<Set<number>>(new Set());

  const nodesById = useMemo(() => new Map(nodes.map((node) => [node.id, node])), [nodes]);

  const renderTreeMemo = useMemo(
    () => buildRenderTree(nodes, mothers, edited),
    [nodes, mothers, edited]
  );

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetchTree(scope ?? undefined);
      const sortedNodes = [...data.nodes].sort((a, b) => a.slotsStart - b.slotsStart);
      setNodes(sortedNodes);
      setMothers(buildEdgeMap(data.edges));
      setEdited(new Set(data.edges.filter((edge) => edge.source === "user").map((edge) => edge.from)));
      setError(null);
    } catch (err) {
      const message = err instanceof Error ? err.message : "데이터를 불러오지 못했습니다.";
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [scope]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const applyEdgeUpdate = useCallback((edge: EdgeDTO) => {
    setMothers((prev) => {
      const next = new Map(prev);
      next.set(edge.from, edge.to ?? null);
      return next;
    });
    setEdited((prev) => {
      const next = new Set(prev);
      if (edge.source === "user") {
        next.add(edge.from);
      } else {
        next.delete(edge.from);
      }
      return next;
    });
  }, []);

  const handleMutation = useCallback(
    async (mutator: () => Promise<EdgeDTO>) => {
      setMutating(true);
      try {
        const edge = await mutator();
        applyEdgeUpdate(edge);
        setError(null);
      } catch (err) {
        const message = err instanceof Error ? err.message : "편집에 실패했습니다.";
        setError(message);
        throw err;
      } finally {
        setTimeout(() => setMutating(false), REFETCH_DELAY);
      }
    },
    [applyEdgeUpdate]
  );

  const reparentNode = useCallback(
    async (child: number, newMother: number) => {
      await handleMutation(() => reparent(child, newMother));
    },
    [handleMutation]
  );

  const rootifyNode = useCallback(
    async (child: number) => {
      await handleMutation(() => rootify(child));
    },
    [handleMutation]
  );

  const undoLast = useCallback(async () => {
    await handleMutation(() => undo());
  }, [handleMutation]);

  const redoLast = useCallback(async () => {
    await handleMutation(() => redo());
  }, [handleMutation]);

  const computeDropTargets = useCallback(
    (childId: number): DropTargets => {
      const node = nodesById.get(childId);
      if (!node) {
        return { nodeTargets: new Set<number>(), allowRoot: false };
      }
      const childrenMap = buildChildrenMap(mothers);
      const forbidden = collectDescendants(childId, childrenMap);
      forbidden.add(childId);

      const targets = new Set<number>();
      nodesById.forEach((candidate, candidateId) => {
        if (forbidden.has(candidateId)) {
          return;
        }
        if (!candidate.draggable) {
          return;
        }
        if (candidateId >= childId) {
          return;
        }
        targets.add(candidateId);
      });
      return { nodeTargets: targets, allowRoot: true };
    },
    [mothers, nodesById]
  );

  const clearError = useCallback(() => setError(null), []);
  const reportError = useCallback((message: string) => setError(message), []);

  return {
    loading,
    mutating,
    error,
    renderTree: renderTreeMemo,
    orderedNodes: nodes,
    nodesById,
    mothers,
    edited,
    refresh,
    reparentNode,
    rootifyNode,
    undoLast,
    redoLast,
    computeDropTargets,
    clearError,
    reportError,
  };
}
