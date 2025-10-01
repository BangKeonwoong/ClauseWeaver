import { memo, type CSSProperties } from "react";
import { useDroppable, useDraggable } from "@dnd-kit/core";
import type { DropTargets } from "../types";
import type { RenderNode } from "../hooks/useTree";

interface TreeViewProps {
  tree: RenderNode[];
  activeDragId: number | null;
  dropTargets: DropTargets | null;
  mutating: boolean;
  selectedId: number | null;
  onSelect: (nodeId: number) => void;
  referenceMap: Map<number, string>;
  highlightParentId: number | null;
  highlightChildIds: number[];
  highlightSiblingIds: number[];
}

export function TreeView({
  tree,
  activeDragId,
  dropTargets,
  mutating,
  selectedId,
  onSelect,
  referenceMap,
  highlightParentId,
  highlightChildIds,
  highlightSiblingIds,
}: TreeViewProps) {
  const allowRoot = dropTargets?.allowRoot ?? false;
  const { isOver: rootIsOver, setNodeRef: setRootRef } = useDroppable({
    id: "root-drop",
    disabled: !allowRoot,
  });

  return (
    <div className="tree">
      <div
        ref={setRootRef}
        className={`root-drop-zone ${allowRoot && rootIsOver ? "active" : ""}`.trim()}
      >
        ⟂ 루트로 드랍하면 어미절이 제거됩니다
      </div>
      {tree.map((renderNode) => (
        <ClauseRow
          key={renderNode.node.id}
          renderNode={renderNode}
          activeDragId={activeDragId}
          dropTargets={dropTargets}
          mutating={mutating}
          onSelect={onSelect}
          selectedId={selectedId}
          referenceMap={referenceMap}
          highlightParent={highlightParentId === renderNode.node.id}
          highlightChild={highlightChildIds.includes(renderNode.node.id)}
          highlightSibling={highlightSiblingIds.includes(renderNode.node.id)}
        />
      ))}
    </div>
  );
}

interface ClauseRowProps {
  renderNode: RenderNode;
  activeDragId: number | null;
  dropTargets: DropTargets | null;
  mutating: boolean;
  selectedId: number | null;
  onSelect: (nodeId: number) => void;
  referenceMap: Map<number, string>;
  highlightParent: boolean;
  highlightChild: boolean;
  highlightSibling: boolean;
}

const ClauseRow = memo(function ClauseRow({
  renderNode,
  activeDragId,
  dropTargets,
  mutating,
  selectedId,
  onSelect,
  referenceMap,
  highlightParent,
  highlightChild,
  highlightSibling,
}: ClauseRowProps) {
  const { node, depth, isEdited, mother } = renderNode;
  const droppableId = `drop-${node.id}`;
  const draggableId = `drag-${node.id}`;

  const isValidTarget = dropTargets?.nodeTargets.has(node.id) ?? false;
  const { isOver, setNodeRef: setDropRef } = useDroppable({
    id: droppableId,
    disabled: !dropTargets || !isValidTarget,
  });

  const { attributes, listeners, setNodeRef: setDragRef, isDragging, transform } = useDraggable({
    id: draggableId,
    disabled: mutating || !node.draggable,
  });

  const style: CSSProperties = {
    paddingLeft: `${depth * 32}px`,
    transform: transform
      ? `translate3d(${transform.x}px, ${transform.y}px, 0)`
      : undefined,
  };

  const stateClass = [
    "node-row",
    node.draggable ? "" : "non-draggable",
    isDragging || activeDragId === node.id ? "dragging" : "",
    dropTargets
      ? isValidTarget
        ? isOver
          ? "valid-target active"
          : "valid-target"
        : "invalid-target"
      : "",
    node.inScope ? "" : "out-of-scope",
    selectedId === node.id ? "selected" : "",
    highlightParent ? "parent" : "",
    highlightChild ? "child" : "",
    highlightSibling ? "sibling" : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div
      ref={setDropRef}
      className={stateClass}
      style={style}
      data-node-id={node.id}
      onClick={() => onSelect(node.id)}
    >
      <div
        ref={setDragRef}
        className="node-label"
        {...listeners}
        {...attributes}
      >
        {node.label}
      </div>
      <div className="node-meta">
        {node.reference || `#${node.id}`} · {node.kind}
        {mother !== null &&
          ` → 어미 ${referenceMap.get(mother) ?? `#${mother}`}`}
      </div>
      {isEdited && <span className="badge">edited</span>}
    </div>
  );
});
