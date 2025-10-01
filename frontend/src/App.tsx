import { useCallback, useEffect, useMemo, useState } from "react";
import {
  DndContext,
  PointerSensor,
  type DragEndEvent,
  type DragStartEvent,
  type DragCancelEvent,
  useSensor,
  useSensors,
} from "@dnd-kit/core";

import { TreeView } from "./components/TreeView";
import { useTree } from "./hooks/useTree";
import type { DropTargets, ClauseNodeDTO } from "./types";
import { shutdown as shutdownApi } from "./api";

const parseDragId = (id: string | number): number | null => {
  if (typeof id !== "string") return null;
  if (!id.startsWith("drag-")) return null;
  const value = Number(id.replace("drag-", ""));
  return Number.isFinite(value) ? value : null;
};

const parseDropId = (id: string | number): number | null => {
  if (typeof id !== "string") return null;
  if (!id.startsWith("drop-")) return null;
  const value = Number(id.replace("drop-", ""));
  return Number.isFinite(value) ? value : null;
};

function App() {
  const [scope, setScope] = useState<string>("Genesis.1");
  const [scopeDraft, setScopeDraft] = useState<string>("Genesis.1");

  const {
    loading,
    mutating,
    error,
    renderTree,
    orderedNodes,
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
  } = useTree(scope);

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 8 },
    })
  );

  const [activeDragId, setActiveDragId] = useState<number | null>(null);
  const [dropTargets, setDropTargets] = useState<DropTargets | null>(null);
  const [pendingAction, setPendingAction] = useState<string | null>(null);
  const [shutdownRequested, setShutdownRequested] = useState(false);
  const [shutdownNotice, setShutdownNotice] = useState<string | null>(null);
  const [selectedNodeId, setSelectedNodeId] = useState<number | null>(null);
  const [annotations, setAnnotations] = useState<Map<number, string>>(() => new Map());
  const [checklists, setChecklists] = useState<Map<number, Record<string, boolean>>>(
    () => new Map()
  );

  const CHECKLIST_ITEMS = useMemo(
    () => [
      { key: "dependency", label: "종속 표지 확인" },
      { key: "speech", label: "직설 전환 확인" },
      { key: "clauseType", label: "절 유형 확인" },
    ],
    []
  );

  const referenceMap = useMemo(() => {
    const map = new Map<number, string>();
    orderedNodes.forEach((node) => {
      map.set(node.id, node.reference);
    });
    return map;
  }, [orderedNodes]);

  const formatReference = useCallback(
    (id: number | null | undefined) => {
      if (id == null) {
        return "—";
      }
      return referenceMap.get(id) ?? `#${id}`;
    },
    [referenceMap]
  );

  const formatTyp = useCallback(
    (id: number | null | undefined) => {
      if (id == null) {
        return "—";
      }
      return nodesById.get(id)?.typ ?? "—";
    },
    [nodesById]
  );

  const applyScope = useCallback(() => {
    const normalized = scopeDraft.trim();
    if (!normalized) {
      reportError("범위를 입력해 주세요.");
      return;
    }
    if (normalized !== scope) {
      setScope(normalized);
    }
  }, [reportError, scopeDraft, scope]);

  const resetDragState = useCallback(() => {
    setActiveDragId(null);
    setDropTargets(null);
  }, []);

  const handleDragStart = useCallback(
    (event: DragStartEvent) => {
      const nodeId = parseDragId(event.active.id);
      if (nodeId == null) return;
      const targets = computeDropTargets(nodeId);
      setActiveDragId(nodeId);
      setDropTargets(targets);
      setSelectedNodeId(nodeId);
      clearError();
    },
    [computeDropTargets, clearError]
  );

  const handleDragCancel = useCallback(
    (_event: DragCancelEvent) => {
      resetDragState();
    },
    [resetDragState]
  );

  const handleDrop = useCallback(
    async (event: DragEndEvent) => {
      const childId = parseDragId(event.active.id);
      if (childId == null) {
        resetDragState();
        return;
      }
      if (!event.over) {
        resetDragState();
        return;
      }
      if (!dropTargets) {
        resetDragState();
        return;
      }

      try {
        if (event.over.id === "root-drop") {
          if (!dropTargets.allowRoot) {
            reportError("루트화가 허용되지 않는 노드입니다.");
            return;
          }
          setPendingAction("rootify");
          await rootifyNode(childId);
        } else {
          const motherId = parseDropId(event.over.id);
          if (motherId == null) {
            reportError("유효하지 않은 드랍 영역입니다.");
            return;
          }
          if (motherId === childId) {
            reportError("같은 노드에는 연결할 수 없습니다.");
            return;
          }
          if (!dropTargets.nodeTargets.has(motherId)) {
            reportError("허용되지 않는 대상입니다.");
            return;
          }
          setPendingAction("reparent");
          await reparentNode(childId, motherId);
        }
      } catch (err) {
        if (err instanceof Error) {
          reportError(err.message);
        }
      } finally {
        setPendingAction(null);
        resetDragState();
      }
    },
    [dropTargets, reparentNode, reportError, resetDragState, rootifyNode]
  );

  const handleDragEnd = useCallback(
    async (event: DragEndEvent) => {
      await handleDrop(event);
    },
    [handleDrop]
  );

  const isBusy = loading || mutating || pendingAction !== null || shutdownRequested;

  const toolbarDisabled = mutating || pendingAction !== null || shutdownRequested;

  const toolbarLabel = useMemo(() => {
    if (loading) return "불러오는 중...";
    if (shutdownRequested) return "프로그램을 종료하는 중...";
    if (mutating || pendingAction) return "변경 적용 중...";
    return "";
  }, [loading, mutating, pendingAction, shutdownRequested]);

  const handleShutdown = useCallback(async () => {
    if (shutdownRequested) {
      return;
    }
    setShutdownRequested(true);
    setShutdownNotice("프로그램을 종료하는 중입니다. 잠시만 기다려 주세요.");
    try {
      await shutdownApi();
      setShutdownNotice("서버 종료 요청이 완료되었습니다. 터미널에서 종료를 확인한 뒤 창을 닫아 주세요.");
    } catch (err) {
      setShutdownRequested(false);
      setShutdownNotice(null);
      if (err instanceof Error) {
        reportError(err.message);
      } else {
        reportError("종료 요청에 실패했습니다.");
      }
    }
  }, [reportError, shutdownRequested]);

  const handleSelectNode = useCallback((nodeId: number) => {
    setSelectedNodeId(nodeId);
  }, []);

  const selectedNode = useMemo(() => {
    if (selectedNodeId == null) {
      return null;
    }
    return nodesById.get(selectedNodeId) ?? null;
  }, [nodesById, selectedNodeId]);

  const selectedChildren = useMemo(() => {
    if (selectedNodeId == null) {
      return [];
    }
    const children: ClauseNodeDTO[] = [];
    mothers.forEach((mother, childId) => {
      if (mother === selectedNodeId) {
        const childNode = nodesById.get(childId);
        if (childNode) {
          children.push(childNode);
        }
      }
    });
    children.sort((a, b) => a.slotsStart - b.slotsStart);
    return children;
  }, [mothers, nodesById, selectedNodeId]);

  const selectionRelations = useMemo(() => {
    if (selectedNodeId == null) {
      return {
        parent: null as ClauseNodeDTO | null,
        siblings: [] as ClauseNodeDTO[],
        children: [] as ClauseNodeDTO[],
        highlightParentId: null as number | null,
        highlightChildIds: [] as number[],
      };
    }
    const parentId = mothers.get(selectedNodeId) ?? null;
    const parentNode = parentId != null ? nodesById.get(parentId) ?? null : null;
    const children = selectedChildren;
    const siblings: ClauseNodeDTO[] = [];
    if (parentId != null) {
      mothers.forEach((mother, childId) => {
        if (mother === parentId && childId !== selectedNodeId) {
          const node = nodesById.get(childId);
          if (node) {
            siblings.push(node);
          }
        }
      });
      siblings.sort((a, b) => a.slotsStart - b.slotsStart);
    }
    return {
      parent: parentNode,
      siblings,
      children,
      highlightParentId: parentId,
      highlightChildIds: children.map((child) => child.id),
      highlightSiblingIds: siblings.map((sibling) => sibling.id),
    };
  }, [mothers, nodesById, selectedNodeId, selectedChildren]);

  const annotationValue = useMemo(() => {
    if (selectedNodeId == null) {
      return "";
    }
    return annotations.get(selectedNodeId) ?? "";
  }, [annotations, selectedNodeId]);

  const checklistState = useMemo(() => {
    if (selectedNodeId == null) {
      return null;
    }
    return (
      checklists.get(selectedNodeId) ??
      CHECKLIST_ITEMS.reduce((acc, item) => {
        acc[item.key] = false;
        return acc;
      }, {} as Record<string, boolean>)
    );
  }, [CHECKLIST_ITEMS, checklists, selectedNodeId]);

  const sameTxtNeighbors = useMemo(() => {
    if (!selectedNode) {
      return { previous: null as ClauseNodeDTO | null, next: null as ClauseNodeDTO | null };
    }
    const index = orderedNodes.findIndex((node) => node.id === selectedNode.id);
    if (index === -1) {
      return { previous: null, next: null };
    }
    let previous: ClauseNodeDTO | null = null;
    for (let i = index - 1; i >= 0; i -= 1) {
      if (orderedNodes[i].txt === selectedNode.txt) {
        previous = orderedNodes[i];
        break;
      }
    }
    let next: ClauseNodeDTO | null = null;
    for (let i = index + 1; i < orderedNodes.length; i += 1) {
      if (orderedNodes[i].txt === selectedNode.txt) {
        next = orderedNodes[i];
        break;
      }
    }
    return { previous, next };
  }, [orderedNodes, selectedNode]);

  const handleAnnotationChange = useCallback(
    (value: string) => {
      if (selectedNodeId == null) {
        return;
      }
      setAnnotations((prev) => {
        const next = new Map(prev);
        next.set(selectedNodeId, value);
        return next;
      });
    },
    [selectedNodeId]
  );

  const clearAnnotation = useCallback(() => {
    if (selectedNodeId == null) {
      return;
    }
    setAnnotations((prev) => {
      const next = new Map(prev);
      next.delete(selectedNodeId);
      return next;
    });
  }, [selectedNodeId]);

  useEffect(() => {
    setSelectedNodeId(null);
  }, [scope]);

  const toggleChecklistItem = useCallback(
    (key: string) => {
      if (selectedNodeId == null) {
        return;
      }
      setChecklists((prev) => {
        const next = new Map(prev);
        const current = { ...(next.get(selectedNodeId) ?? {}) };
        current[key] = !current[key];
        next.set(selectedNodeId, current);
        return next;
      });
    },
    [selectedNodeId]
  );

  return (
    <DndContext
      sensors={sensors}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
      onDragCancel={handleDragCancel}
    >
      <div className="app">
        <div className="header">
          <div className="header-left">
            <h1>어미절 재부모화 도구</h1>
            <p className="scope-label">현재 범위: {scope}</p>
          </div>
          <div className="header-right">
            <div className="scope-input">
              <label>
                범위
                <input
                  value={scopeDraft}
                  onChange={(event) => setScopeDraft(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      applyScope();
                    }
                  }}
                  disabled={isBusy}
                />
              </label>
              <button
                type="button"
                className="secondary"
                onClick={applyScope}
                disabled={isBusy}
              >
                적용
              </button>
            </div>
            <div className="toolbar">
              <button
                type="button"
                className="secondary"
                onClick={() => undoLast().catch(() => undefined)}
                disabled={toolbarDisabled}
              >
                ↩︎ Undo
              </button>
              <button
                type="button"
                className="secondary"
                onClick={() => redoLast().catch(() => undefined)}
                disabled={toolbarDisabled}
              >
                ↪︎ Redo
              </button>
              <button
                type="button"
                onClick={() => {
                  setPendingAction("refresh");
                  refresh()
                    .catch((err) => {
                      if (err instanceof Error) {
                        reportError(err.message);
                      }
                    })
                    .finally(() => setPendingAction(null));
                }}
                disabled={toolbarDisabled}
              >
                새로고침
              </button>
              <button
                type="button"
                className="danger"
                onClick={handleShutdown}
                disabled={shutdownRequested}
              >
                종료
              </button>
            </div>
          </div>
        </div>
        {toolbarLabel && <p>{toolbarLabel}</p>}
        {shutdownNotice && <div className="info-banner">{shutdownNotice}</div>}
        <div className="app-body">
          <div className="tree-wrapper">
            <TreeView
              tree={renderTree}
              activeDragId={activeDragId}
              dropTargets={dropTargets}
              mutating={isBusy}
              selectedId={selectedNodeId}
              onSelect={handleSelectNode}
              referenceMap={referenceMap}
              highlightParentId={selectionRelations.highlightParentId}
              highlightChildIds={selectionRelations.highlightChildIds ?? []}
              highlightSiblingIds={selectionRelations.highlightSiblingIds ?? []}
            />
          </div>
          <aside className="info-panel">
            <h2>절 정보</h2>
            {selectedNode ? (
              <div className="info-content">
                <div className="info-section">
                  <h3>기본</h3>
                  <dl className="info-list">
                    <div>
                      <dt>주소</dt>
                      <dd>{selectedNode.reference ?? selectedNode.id}</dd>
                    </div>
                    <div>
                      <dt>범위</dt>
                      <dd>{selectedNode.containerId}</dd>
                    </div>
                    <div>
                      <dt>슬롯</dt>
                      <dd>
                        {selectedNode.slotsStart} – {selectedNode.slotsEnd} ({selectedNode.slotCount})
                      </dd>
                    </div>
                    <div>
                      <dt>히브리어</dt>
                      <dd className="hebrew-text">{selectedNode.label}</dd>
                    </div>
                    <div>
                      <dt>사용자 수정</dt>
                      <dd>{edited.has(selectedNode.id) ? "예" : "아니오"}</dd>
                    </div>
                  </dl>
                </div>
                <div className="info-section">
                  <h3>형태 / 관계</h3>
                  <dl className="info-list">
                    <div>
                      <dt>Typ</dt>
                      <dd>{selectedNode.typ ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>어미 Typ</dt>
                      <dd>{formatTyp(mothers.get(selectedNode.id) ?? null)}</dd>
                    </div>
                    <div>
                      <dt>Rela</dt>
                      <dd>{selectedNode.rela ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>Code</dt>
                      <dd>{selectedNode.code ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>Txt</dt>
                      <dd>{selectedNode.txt ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>Domain</dt>
                      <dd>{selectedNode.domain ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>Instruction</dt>
                      <dd>{selectedNode.instruction ?? "—"}</dd>
                    </div>
                    <div>
                      <dt>핵심 기능</dt>
                      <dd>
                        {selectedNode.coreFunctions.length > 0
                          ? selectedNode.coreFunctions.join(", ")
                          : "—"}
                      </dd>
                    </div>
                  </dl>
                </div>
                <div className="info-section">
                  <h3>계층</h3>
                  <dl className="info-list">
                    <div>
                      <dt>원본 어미</dt>
                      <dd>{formatReference(selectedNode.originalMother)}</dd>
                    </div>
                    <div>
                      <dt>현재 어미</dt>
                      <dd>{formatReference(mothers.get(selectedNode.id) ?? null)}</dd>
                    </div>
                    <div>
                      <dt>자식 절</dt>
                      <dd>
                        {selectedNode.children.length === 0
                          ? "없음"
                          : selectedNode.children
                              .map((child) =>
                                `${nodesById.get(child.id)?.reference ?? `#${child.id}`} (${child.rela ?? "?"}${child.code ? `, ${child.code}` : ""})`
                              )
                              .join("; ")}
                      </dd>
                    </div>
                    <div>
                      <dt>현재 자식</dt>
                      <dd>
                        {selectedChildren.length === 0
                          ? "없음"
                          : selectedChildren
                              .map((child) =>
                                `${child.reference ?? `#${child.id}`} (${child.rela ?? "?"}${child.code ? `, ${child.code}` : ""})`
                              )
                              .join("; ")}
                      </dd>
                    </div>
                  </dl>
                </div>
                <div className="info-section">
                  <h3>담화</h3>
                  <dl className="info-list">
                    <div>
                      <dt>TXT / Domain</dt>
                      <dd>
                        {selectedNode.txt ?? "—"}
                        {selectedNode.domain ? ` (${selectedNode.domain})` : ""}
                      </dd>
                    </div>
                    <div>
                      <dt>동일 txt 이전</dt>
                      <dd>
                        {sameTxtNeighbors.previous
                          ? sameTxtNeighbors.previous.reference ?? `#${sameTxtNeighbors.previous.id}`
                          : "없음"}
                      </dd>
                    </div>
                    <div>
                      <dt>동일 txt 다음</dt>
                      <dd>
                        {sameTxtNeighbors.next
                          ? sameTxtNeighbors.next.reference ?? `#${sameTxtNeighbors.next.id}`
                          : "없음"}
                      </dd>
                    </div>
                  </dl>
                </div>
                <div className="info-section">
                  <h3>주석</h3>
                  <textarea
                    value={annotationValue}
                    onChange={(event) => handleAnnotationChange(event.target.value)}
                    placeholder="이 절에 대한 메모를 입력하세요."
                    rows={6}
                  />
                  <div className="info-actions">
                    <button
                      type="button"
                      className="secondary"
                      onClick={clearAnnotation}
                      disabled={annotationValue.length === 0}
                    >
                      주석 초기화
                    </button>
                  </div>
                </div>
                <div className="info-section">
                  <h3>체크리스트</h3>
                  <div className="checklist">
                    {CHECKLIST_ITEMS.map((item) => (
                      <label key={item.key}>
                        <input
                          type="checkbox"
                          checked={Boolean(checklistState?.[item.key])}
                          onChange={() => toggleChecklistItem(item.key)}
                        />
                        {item.label}
                      </label>
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              <p className="info-placeholder">왼쪽 목록에서 절을 선택하면 정보가 표시됩니다.</p>
            )}
          </aside>
        </div>
        {error && (
          <div className="error-banner">
            <strong>오류:</strong> {error}
            <button
              type="button"
              className="secondary"
              style={{ marginLeft: "0.75rem" }}
              onClick={clearError}
            >
              닫기
            </button>
          </div>
        )}
      </div>
    </DndContext>
  );
}

export default App;
