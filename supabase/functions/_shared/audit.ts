import { logWarn } from "./redact.ts";

type RpcClient = {
  rpc: (
    functionName: string,
    params: Record<string, unknown>,
  ) => unknown;
};

interface AuditEventParams {
  companyId: string;
  action: string;
  entityType: string;
  entityId?: string | null;
  outcome?: "success" | "failure" | "denied";
  correlationId?: string | null;
  metadata?: Record<string, unknown>;
}

export async function recordAuditEvent(
  client: RpcClient,
  params: AuditEventParams,
): Promise<void> {
  const { error } = await client.rpc("record_security_audit_event", {
    p_company_id: params.companyId,
    p_action: params.action,
    p_entity_type: params.entityType,
    p_entity_id: params.entityId ?? null,
    p_outcome: params.outcome ?? "success",
    p_correlation_id: params.correlationId ?? null,
    p_metadata: params.metadata ?? {},
  }) as { error: { message?: string } | null };

  if (error) {
    logWarn(`[audit] failed to record event action=${params.action} error=${error.message ?? "unknown"}`);
  }
}

export function recordAuditEventDeferred(
  client: RpcClient,
  params: AuditEventParams,
): void {
  const task = recordAuditEvent(client, params).catch((error) => {
    logWarn(`[audit] failed to record event action=${params.action} error=${error}`);
  });

  const edgeRuntime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (promise: Promise<void>) => void };
  }).EdgeRuntime;

  if (edgeRuntime?.waitUntil) {
    edgeRuntime.waitUntil(task);
  }
}