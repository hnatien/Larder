/** Builds a JSON response carrying the request id header every proxy response must have. */
export function json(status: number, body: unknown, requestId: string): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "x-request-id": requestId },
  });
}

/** A status plus JSON body, produced by layers that do not know the request id. */
export interface ErrorReply {
  status: number;
  body: { error: string } & Record<string, unknown>;
}

/** Shorthand for an `ErrorReply`. */
export function errorReply(status: number, error: string, extra: Record<string, unknown> = {}): ErrorReply {
  return { status, body: { error, ...extra } };
}
