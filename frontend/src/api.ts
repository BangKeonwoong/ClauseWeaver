import type { EdgeDTO, TreeResponseDTO } from "./types";

const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? "/api";

async function handleResponse<T>(response: Response): Promise<T> {
  if (response.ok) {
    return (await response.json()) as T;
  }
  const text = await response.text();
  try {
    const data = JSON.parse(text);
    throw new Error(data.reason ?? text ?? "UNKNOWN_ERROR");
  } catch {
    throw new Error(text || "Request failed");
  }
}

export async function fetchTree(scope?: string): Promise<TreeResponseDTO> {
  const params = scope ? `?scope=${encodeURIComponent(scope)}` : "";
  const res = await fetch(`${API_BASE}/tree${params}`);
  return handleResponse<TreeResponseDTO>(res);
}

export async function reparent(child: number, newMother: number): Promise<EdgeDTO> {
  const res = await fetch(`${API_BASE}/mother/reparent`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ child, newMother }),
  });
  const data = await handleResponse<{ edge: EdgeDTO }>(res);
  return data.edge;
}

export async function rootify(child: number): Promise<EdgeDTO> {
  const res = await fetch(`${API_BASE}/mother/rootify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ child }),
  });
  const data = await handleResponse<{ edge: EdgeDTO }>(res);
  return data.edge;
}

export async function undo(): Promise<EdgeDTO> {
  const res = await fetch(`${API_BASE}/mother/undo`, { method: "POST" });
  const data = await handleResponse<{ edge: EdgeDTO }>(res);
  return data.edge;
}

export async function redo(): Promise<EdgeDTO> {
  const res = await fetch(`${API_BASE}/mother/redo`, { method: "POST" });
  const data = await handleResponse<{ edge: EdgeDTO }>(res);
  return data.edge;
}

export async function shutdown(): Promise<void> {
  const res = await fetch(`${API_BASE}/shutdown`, { method: "POST" });
  await handleResponse<{ ok: boolean; message?: string }>(res);
}
