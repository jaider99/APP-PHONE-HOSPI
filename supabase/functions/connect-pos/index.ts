import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { HttpError, readJsonObject, requireStringField } from "../_shared/request.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const supportedCountryCodes = new Set([
  "ES",
  "US",
  "GB",
  "FR",
  "IT",
  "DE",
  "CO",
  "MX",
  "PT",
  "NL",
  "OTHER",
]);

interface PosProviderCatalogRow {
  provider_key: string;
  display_name: string;
  country_codes: string[];
  connection_type: string;
  status: string;
  description: string | null;
  connection_mode: string;
  connection_status: string;
  supports_oauth: boolean;
  supports_api_key: boolean;
  supports_file_import: boolean;
  supports_email_invite: boolean;
  has_backend_adapter: boolean;
  edge_function_name: string | null;
  documentation_url: string | null;
  notes: string | null;
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
  if (req.method !== "POST") {
    return jsonResponse({ message: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new HttpError(401, "Missing authorization");

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    throw new HttpError(500, "POS connection service is not configured");
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
    maxBytes: 768,
    allowedFields: ["country_code", "provider", "provider_key", "connection_mode"],
  });
  const countryCode = requireStringField(body, "country_code", { maxLength: 16 })
    .toUpperCase();
  const providerKey = requireProviderKey(body);
  const requestedConnectionMode = optionalStringField(body, "connection_mode", 64);

  if (!supportedCountryCodes.has(countryCode)) {
    throw new HttpError(400, "Unsupported country for POS connections");
  }

  const companyId = await resolveActiveCompanyId(serviceClient, user.id);
  if (!companyId) throw new HttpError(403, "No active company for this user");

  const provider = await fetchProvider(serviceClient, providerKey);
  if (!provider) throw new HttpError(404, "POS provider is not available");
  if (!providerSupportsCountry(provider, countryCode)) {
    throw new HttpError(400, "This POS provider is not available in the selected country");
  }

  if (requestedConnectionMode && requestedConnectionMode !== provider.connection_mode) {
    throw new HttpError(400, "This POS connection mode is not available for the selected provider");
  }

  if (isImportConnection(provider)) {
    return createImportConnection(serviceClient, {
      companyId,
      userId: user.id,
      countryCode,
      provider,
    });
  }

  if (provider.has_backend_adapter && isNativeMode(provider.connection_mode)) {
    return jsonResponse({
      status: "native_not_ready",
      message: "This native POS sync path is not enabled yet. Import a sales report while setup is completed.",
      connection_mode: provider.connection_mode,
      next_action: "import_report",
      import_fallback: true,
    });
  }

  return createConnectionRequest(serviceClient, {
    companyId,
    userId: user.id,
    countryCode,
    provider,
  });
}

function requireProviderKey(body: Record<string, unknown>): string {
  if (body.provider !== undefined && body.provider_key !== undefined) {
    throw new HttpError(400, "Send either provider or provider_key, not both");
  }
  return requireStringField(
    body,
    body.provider_key !== undefined ? "provider_key" : "provider",
    { maxLength: 64 },
  ).toLowerCase();
}

function optionalStringField(
  body: Record<string, unknown>,
  field: string,
  maxLength: number,
): string | null {
  const value = body[field];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `${field} must be a non-empty string`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) throw new HttpError(413, `${field} is too large`);
  return trimmed;
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

async function fetchProvider(
  client: any,
  providerKey: string,
): Promise<PosProviderCatalogRow | null> {
  const { data, error } = await client
    .from("pos_provider_catalog")
    .select(
      "provider_key, display_name, countries, country_codes, connection_type, status, " +
        "description, connection_mode, connection_status, supports_oauth, supports_api_key, " +
        "supports_file_import, supports_email_invite, has_backend_adapter, edge_function_name, " +
        "documentation_url, notes",
    )
    .eq("provider_key", providerKey)
    .maybeSingle();
  if (error) throw new HttpError(500, "Could not load POS provider catalog");
  if (!data) return null;
  return {
    provider_key: data.provider_key,
    display_name: data.display_name,
    country_codes: Array.isArray(data.country_codes)
      ? data.country_codes
      : Array.isArray(data.countries)
      ? data.countries
      : [],
    connection_type: data.connection_type,
    status: data.status,
    description: data.description,
    connection_mode: data.connection_mode,
    connection_status: data.connection_status,
    supports_oauth: data.supports_oauth === true,
    supports_api_key: data.supports_api_key === true,
    supports_file_import: data.supports_file_import !== false,
    supports_email_invite: data.supports_email_invite === true,
    has_backend_adapter: data.has_backend_adapter === true,
    edge_function_name: data.edge_function_name,
    documentation_url: data.documentation_url,
    notes: data.notes,
  };
}

function providerSupportsCountry(provider: PosProviderCatalogRow, countryCode: string) {
  return provider.country_codes.includes(countryCode) || provider.country_codes.includes("OTHER");
}

function isImportConnection(provider: PosProviderCatalogRow) {
  return provider.connection_mode === "custom" ||
    provider.connection_mode === "import_reports" ||
    provider.connection_status === "import_only";
}

function isNativeMode(connectionMode: string) {
  return connectionMode === "native_oauth" || connectionMode === "native_api_key";
}

async function createImportConnection(
  client: any,
  input: {
    companyId: string;
    userId: string;
    countryCode: string;
    provider: PosProviderCatalogRow;
  },
) {
  const { data: existing, error: existingError } = await client
    .from("pos_connections")
    .select("id")
    .eq("company_id", input.companyId)
    .eq("provider_key", input.provider.provider_key)
    .eq("country_code", input.countryCode)
    .eq("connection_mode", input.provider.connection_mode)
    .is("deleted_at", null)
    .in("status", ["connected", "pending"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existingError) throw new HttpError(500, "Could not load POS import connection");

  if (existing) {
    return jsonResponse({
      status: "connected_import_mode",
      message: `${input.provider.display_name} report import is ready. Upload a sales report to start.`,
      connection_id: existing.id,
      connection_mode: input.provider.connection_mode,
      next_action: "import_report",
      import_fallback: true,
    });
  }

  const { data, error } = await client
    .from("pos_connections")
    .insert({
      company_id: input.companyId,
      provider: input.provider.provider_key,
      provider_key: input.provider.provider_key,
      provider_name: input.provider.display_name,
      country_code: input.countryCode,
      connection_type: "file_import",
      connection_mode: input.provider.connection_mode,
      status: "connected",
      credentials_status: "none",
      sync_status: "import_only",
      created_by: input.userId,
      metadata: {
        catalog_status: input.provider.status,
        connection_status: input.provider.connection_status,
        requested_via: "connect_pos_screen",
        stores_pos_credentials: false,
      },
    })
    .select("id")
    .single();
  if (error) throw new HttpError(500, "Could not create custom POS connection");

  return jsonResponse({
    status: "connected_import_mode",
    message: `${input.provider.display_name} report import is ready. Upload a sales report to start.`,
    connection_id: data.id,
    connection_mode: input.provider.connection_mode,
    next_action: "import_report",
    import_fallback: true,
  });
}

async function createConnectionRequest(
  client: any,
  input: {
    companyId: string;
    userId: string;
    countryCode: string;
    provider: PosProviderCatalogRow;
  },
) {
  const { data: existing, error: existingError } = await client
    .from("pos_connection_requests")
    .select("id")
    .eq("company_id", input.companyId)
    .eq("provider_key", input.provider.provider_key)
    .eq("country_code", input.countryCode)
    .in("status", ["requested", "notified"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existingError) throw new HttpError(500, "Could not load POS connection request");

  if (existing) {
    return jsonResponse({
      status: "request_saved",
      message: "Your POS integration request is already saved. Import a sales report while we prepare support.",
      request_id: existing.id,
      connection_mode: input.provider.connection_mode,
      next_action: "import_report",
      import_fallback: true,
    });
  }

  const { data, error } = await client
    .from("pos_connection_requests")
    .insert({
      company_id: input.companyId,
      provider_key: input.provider.provider_key,
      provider_name: input.provider.display_name,
      country_code: input.countryCode,
      status: "requested",
      requested_by: input.userId,
      metadata: {
        connection_type: input.provider.connection_type,
        connection_mode: input.provider.connection_mode,
        connection_status: input.provider.connection_status,
        has_backend_adapter: input.provider.has_backend_adapter,
        supports_oauth: input.provider.supports_oauth,
        supports_api_key: input.provider.supports_api_key,
        supports_file_import: input.provider.supports_file_import,
        supports_email_invite: input.provider.supports_email_invite,
        requested_via: "connect_pos_screen",
      },
    })
    .select("id")
    .single();
  if (error) throw new HttpError(500, "Could not save POS connection request");

  return jsonResponse({
    status: "request_saved",
    message: "We saved your POS integration request. Import a sales report while we prepare support.",
    request_id: data.id,
    connection_mode: input.provider.connection_mode,
    next_action: "import_report",
    import_fallback: true,
  });
}

function handleError(error: unknown) {
  if (error instanceof HttpError) {
    return jsonResponse({ message: error.message }, error.status);
  }

  console.error("connect-pos failed", error);
  return jsonResponse(
    { message: "POS connection request could not be completed. Please try again." },
    500,
  );
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}