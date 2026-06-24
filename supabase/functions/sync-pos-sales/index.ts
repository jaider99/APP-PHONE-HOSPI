import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { HttpError, readJsonObject, requireStringField } from "../_shared/request.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PosConnectionRow {
  id: string;
  company_id: string;
  provider_key: string;
  connection_mode: string;
  status: string;
}

interface PosProviderCatalogRow {
  provider_key: string;
  connection_mode: string;
  connection_status: string;
  has_backend_adapter: boolean;
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
  if (req.method !== "POST") return jsonResponse({ message: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new HttpError(401, "Missing authorization");

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    throw new HttpError(500, "POS sync service is not configured");
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) throw new HttpError(401, "Invalid or expired token");

  const body = await readJsonObject(req, {
    maxBytes: 512,
    allowedFields: ["companyId", "connectionId", "connection_id"],
  });
  const connectionId = requireConnectionId(body);
  const companyId = await resolveActiveCompanyId(serviceClient, user.id);
  if (!companyId) throw new HttpError(403, "No active company for this user");

  const connection = await fetchConnection(serviceClient, companyId, connectionId);
  if (!connection) throw new HttpError(404, "POS connection not found");

  const provider = await fetchProvider(serviceClient, connection.provider_key);
  if (!provider || !provider.has_backend_adapter || !isNativeMode(provider.connection_mode)) {
    return jsonResponse({
      ok: false,
      status: "adapter_not_ready",
      message: "Native POS sync is not available for this provider yet. Import a sales report instead.",
      next_action: "import_report",
    });
  }

  if (connection.status !== "connected") {
    throw new HttpError(409, "POS connection is not connected");
  }

  const { data, error } = await serviceClient.from("pos_sync_jobs")
    .insert({ company_id: companyId, pos_connection_id: connectionId, status: "pending" })
    .select("id, company_id, pos_connection_id, status")
    .single();
  if (error) throw new HttpError(500, "Could not create POS sync job");
  return jsonResponse({ ok: true, job: data });
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

async function resolveActiveCompanyId(client: any, userId: string): Promise<string | null> {
  const { data: profile, error: profileError } = await client
    .from("profiles")
    .select("current_company_id")
    .eq("id", userId)
    .maybeSingle();
  if (profileError) throw new HttpError(500, "Could not resolve active company");

  const currentCompanyId = profile?.current_company_id as string | null | undefined;
  if (currentCompanyId && await userBelongsToCompany(client, currentCompanyId, userId)) {
    return currentCompanyId;
  }

  const { data: membership, error: membershipError } = await client
    .from("company_users")
    .select("company_id")
    .eq("user_id", userId)
    .eq("is_active", true)
    .order("joined_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (membershipError) throw new HttpError(500, "Could not resolve active company");

  return membership?.company_id ?? null;
}

async function userBelongsToCompany(client: any, companyId: string, userId: string) {
  const { data, error } = await client
    .from("company_users")
    .select("company_id")
    .eq("company_id", companyId)
    .eq("user_id", userId)
    .eq("is_active", true)
    .maybeSingle();
  if (error) throw new HttpError(500, "Could not verify company access");
  return !!data;
}

async function fetchConnection(
  client: any,
  companyId: string,
  connectionId: string,
): Promise<PosConnectionRow | null> {
  const { data, error } = await client
    .from("pos_connections")
    .select("id, company_id, provider_key, connection_mode, status")
    .eq("id", connectionId)
    .eq("company_id", companyId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) throw new HttpError(500, "Could not load POS connection");
  return data as PosConnectionRow | null;
}

async function fetchProvider(client: any, providerKey: string): Promise<PosProviderCatalogRow | null> {
  const { data, error } = await client
    .from("pos_provider_catalog")
    .select("provider_key, connection_mode, connection_status, has_backend_adapter")
    .eq("provider_key", providerKey)
    .maybeSingle();
  if (error) throw new HttpError(500, "Could not load POS provider catalog");
  return data as PosProviderCatalogRow | null;
}

function isNativeMode(connectionMode: string) {
  return connectionMode === "native_oauth" || connectionMode === "native_api_key";
}

function handleError(error: unknown) {
  if (error instanceof HttpError) {
    return jsonResponse({ message: error.message }, error.status);
  }

  console.error("sync-pos-sales failed", error);
  return jsonResponse(
    { message: "POS sync could not be started. Please try again." },
    500,
  );
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}