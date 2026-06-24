import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { HttpError, readJsonObject, requireStringField } from "../_shared/request.ts";

const jsonHeaders = { "Content-Type": "application/json" };

interface PosConnectionRow {
  id: string;
  company_id: string;
}

serve(async (req) => {
  try {
    return await handleRequest(req);
  } catch (error) {
    return handleError(error);
  }
});

async function handleRequest(req: Request) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: jsonHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new HttpError(401, "Missing authorization");

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) throw new HttpError(401, "Invalid or expired token");

  const body = await readJsonObject(req, {
    maxBytes: 512,
    allowedFields: ["companyId", "connectionId", "connection_id"],
  });
  const connectionId = requireConnectionId(body);

  const { data: connection, error: connectionError } = await serviceClient
    .from("pos_connections")
    .select("id, company_id")
    .eq("id", connectionId)
    .maybeSingle<PosConnectionRow>();
  if (connectionError || !connection) {
    throw new HttpError(404, "POS connection not found");
  }

  if (!await userIsCompanyAdmin(userClient, connection.company_id, user.id)) {
    throw new HttpError(403, "Access denied");
  }

  const { error } = await serviceClient.from("pos_connections")
    .update({
      status: "disconnected",
      credentials_status: "none",
      access_token_encrypted: null,
      refresh_token_encrypted: null,
      sync_status: "disconnected",
      updated_at: new Date().toISOString(),
    })
    .eq("company_id", connection.company_id)
    .eq("id", connectionId);
  if (error) throw new HttpError(500, "Could not disconnect POS connection");
  return jsonResponse({ ok: true });
}

function requireConnectionId(body: Record<string, unknown>): string {
  if (body.connectionId !== undefined && body.connection_id !== undefined) {
    throw new HttpError(400, "Send either connectionId or connection_id, not both");
  }
  return requireStringField(
    body,
    body.connection_id !== undefined ? "connection_id" : "connectionId",
    { maxLength: 64 },
  );
}

async function userIsCompanyAdmin(client: any, companyId: string, userId: string) {
  const { data, error } = await client.from("company_users")
    .select("company_id, role")
    .eq("company_id", companyId)
    .eq("user_id", userId)
    .eq("is_active", true)
    .in("role", ["owner", "admin"])
    .maybeSingle();
  return !error && !!data;
}

function handleError(error: unknown) {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }

  console.error("disconnect-pos failed", error);
  return jsonResponse(
    { error: "POS connection could not be disconnected. Please try again." },
    500,
  );
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}