export interface Template {
  id: string;
  version: number;
  title: string;
  steps: string[];
}

export interface Run {
  id: string;
  template_id: string;
  template_version: number;
  template_title: string;
  label: string;
  total_steps: number;
  completed_steps: number;
  completed_at: string | null;
  created_at: string;
}

export interface Step {
  run_id: string;
  step_number: number;
  title: string;
}

export interface Completion {
  run_id: string;
  step_number: number;
  note: string;
  completed_at: string;
}

export interface RunDetail extends Run {
  run_steps: Step[];
  completions: Completion[];
}

export type Action =
  | {
      kind: "start";
      payload: { p_request_id: string; p_template_id: string; p_label: string };
    }
  | {
      kind: "complete";
      payload: {
        p_request_id: string;
        p_run_id: string;
        p_step_number: number;
        p_note: string;
      };
    };

export interface MutationResult {
  run_id: string;
  completed_steps: number;
  status: "open" | "completed";
}

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export async function request<T>(
  token: string,
  path: string,
  options: { signal?: AbortSignal; payload?: unknown } = {},
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`/api/${path}`, {
      method: options.payload === undefined ? "GET" : "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        ...(options.payload === undefined
          ? {}
          : { "Content-Type": "application/json" }),
      },
      credentials: "omit",
      signal: options.signal,
      body:
        options.payload === undefined
          ? undefined
          : JSON.stringify(options.payload),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError")
      throw error;
    throw new ApiError(
      "The response did not arrive. Retry the same action to check its result.",
      0,
    );
  }
  const data: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 401) {
      throw new ApiError(
        "This token is missing, invalid or expired. Disconnect and connect with a fresh token.",
        401,
      );
    }
    const safeMessage =
      data &&
      typeof data === "object" &&
      "message" in data &&
      typeof data.message === "string"
        ? data.message
        : "The action could not be confirmed. Retry it or refresh the run.";
    throw new ApiError(safeMessage, response.status);
  }
  if (data === null)
    throw new ApiError(
      "The response could not be read. Retry the same action.",
      0,
    );
  return data as T;
}

export function submit(token: string, action: Action): Promise<MutationResult> {
  return request(
    token,
    `rpc/${action.kind === "start" ? "start_run" : "complete_step"}`,
    {
      payload: action.payload,
    },
  );
}
