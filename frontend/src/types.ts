export interface ClauseNodeDTO {
  id: number;
  slotsStart: number;
  slotsEnd: number;
  slotCount: number;
  label: string;
  containerId: string;
  inScope: boolean;
  kind: string;
  draggable: boolean;
  typ: string | null;
  rela: string | null;
  code: string | null;
  txt: string | null;
  domain: string | null;
  instruction: string | null;
  originalMother: number | null;
  coreFunctions: string[];
  children: RelatedClauseDTO[];
  reference: string;
}

export interface RelatedClauseDTO {
  id: number;
  typ: string | null;
  rela: string | null;
  code: string | null;
}

export type EdgeSource = "original" | "user";

export interface EdgeDTO {
  from: number;
  to: number | null;
  source: EdgeSource;
}

export interface TreeResponseDTO {
  nodes: ClauseNodeDTO[];
  edges: EdgeDTO[];
  scope?: string | null;
  version: string;
}

export interface DropTargets {
  nodeTargets: Set<number>;
  allowRoot: boolean;
}
