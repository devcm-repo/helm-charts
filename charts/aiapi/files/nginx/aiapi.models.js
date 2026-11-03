import fs from "fs";

const cpaConfigPath = "/run/secrets/cliproxyapi-config.yaml";
const DIRECT_COMPAT_PROFILE = {
  tool_mode: "direct",
  use_responses_lite: false,
  supports_search_tool: false,
  prefer_websockets: false,
  multi_agent_version: null,
};
const CONTEXT_WINDOW_RULES = [
  { pattern: /^gpt-.+-(sol|luna|terra)$/, context_window: 512 * 1024 },
];

function send(r, status, body) {
  r.headersOut["Content-Type"] = "application/json";
  r.headersOut["Cache-Control"] = "no-store";
  r.return(status, JSON.stringify(body));
}

export function cpaAuthorizationFromConfig(config) {
  const lines = typeof config === "string" ? config.split(/\r?\n/) : [];
  let listIndent = -1;

  for (const line of lines) {
    const key = line.match(/^(\s*)api-keys\s*:\s*(?:#.*)?$/);
    if (key) {
      listIndent = key[1].length;
      continue;
    }
    if (listIndent < 0 || /^\s*(?:#.*)?$/.test(line)) continue;

    const indent = (line.match(/^\s*/) || [""])[0].length;
    const item = line.match(/^\s*-\s*(.*?)\s*$/);
    if (item && indent >= listIndent) {
      const raw = item[1].replace(/\s+#.*$/, "").trim();
      const keyValue = /^(["'])(.*)\1$/.test(raw) ? raw.slice(1, -1) : raw;
      return keyValue ? "Bearer " + keyValue : "";
    }
    if (indent <= listIndent) break;
  }
  return "";
}

export function cpaAuthorization() {
  try {
    return cpaAuthorizationFromConfig(fs.readFileSync(cpaConfigPath, "utf8"));
  } catch (_) {
    return "";
  }
}

function yamlScalar(raw) {
  const value = raw.replace(/\s+#.*$/, "").trim();
  return /^(?:"([^"]*)"|'([^']*)')$/.test(value)
    ? value.slice(1, -1)
    : value;
}

function routeForSection(section) {
  if (section === "openai-compatibility") {
    return { kind: "direct_compat", protocol: "openai_compat" };
  }
  if (section === "codex-api-key" || section === "xai-api-key") {
    return { kind: "direct_compat", protocol: "third_party_responses" };
  }
  return null;
}

export function cpaTransportRoutesFromConfig(config) {
  const routes = {};
  const lines = typeof config === "string" ? config.split(/\r?\n/) : [];
  let section = "";
  let modelsIndent = -1;
  let model = null;

  const commit = () => {
    if (!model || !model.name) return;
    const id = model.alias || model.name;
    const next = routeForSection(section);
    const current = routes[id];
    if (!current || next.protocol === "third_party_responses") routes[id] = next;
    model = null;
  };

  for (const line of lines) {
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const indent = (line.match(/^\s*/) || [""])[0].length;
    const topLevel = indent === 0 && line.match(/^([a-z0-9-]+)\s*:/i);
    if (topLevel) {
      commit();
      section = routeForSection(topLevel[1]) ? topLevel[1] : "";
      modelsIndent = -1;
      continue;
    }
    if (!section) continue;

    const models = line.match(/^\s*models\s*:\s*(?:#.*)?$/);
    if (models) {
      commit();
      modelsIndent = indent;
      continue;
    }
    if (modelsIndent < 0) continue;

    const name = line.match(/^\s*-\s*name\s*:\s*(.*?)\s*$/);
    if (name && indent >= modelsIndent) {
      commit();
      model = { name: yamlScalar(name[1]), alias: "" };
      continue;
    }
    if (indent < modelsIndent || (indent === modelsIndent && !/^\s*-/.test(line))) {
      commit();
      modelsIndent = -1;
      continue;
    }
    const alias = line.match(/^\s*alias\s*:\s*(.*?)\s*$/);
    if (model && alias) model.alias = yamlScalar(alias[1]);
  }
  commit();
  return routes;
}

export function cpaTransportRoutes() {
  try {
    return cpaTransportRoutesFromConfig(fs.readFileSync(cpaConfigPath, "utf8"));
  } catch (_) {
    return {};
  }
}

export function applyTransportProfile(model, route) {
  if (route.kind === "official_codex") return model;
  return Object.assign(model, DIRECT_COMPAT_PROFILE);
}

function transportRoute(model, route) {
  if (route) return route;
  if (model.supports_search_tool === true) return { kind: "official_codex" };
  return { kind: "direct_compat", protocol: "openai_compat" };
}

export function applyVerifiedCapabilities(model, route) {
  if (route.protocol === "openai_compat") {
    model.apply_patch_tool_type = "freeform";
    return model;
  }
  if (route.protocol !== "third_party_responses") return model;

  model.input_modalities = ["text"];
  model.supports_image_detail_original = false;
  return model;
}

export function buildModels(source, cpaCatalog, cpaRoutes = {}) {
  if (!source || !Array.isArray(source.data)) throw new Error("invalid AIAPI models response");
  if (!cpaCatalog || !Array.isArray(cpaCatalog.models)) throw new Error("invalid CPA Codex catalog");
  if (!cpaRoutes || typeof cpaRoutes !== "object" || Array.isArray(cpaRoutes)) {
    throw new Error("invalid CPA transport routes");
  }

  const catalog = {};
  for (const candidate of cpaCatalog.models) {
    const slug = candidate && typeof candidate.slug === "string" ? candidate.slug.trim() : "";
    if (slug) catalog[slug] = candidate;
  }

  const seen = {};
  const models = [];

  for (const item of source.data) {
    const raw = typeof item === "string" ? item : item && item.id;
    const id = typeof raw === "string" ? raw.trim() : "";
    if (!id || seen[id]) continue;

    const template = catalog[id];
    if (!template) continue;
    const route = transportRoute(template, cpaRoutes[id]);
    const model = applyVerifiedCapabilities(
      applyTransportProfile(Object.assign({}, template), route),
      route,
    );
    const slug = model.slug.toLowerCase().split("/").pop();
    const contextRule = CONTEXT_WINDOW_RULES.find(rule => rule.pattern.test(slug));
    if (contextRule) model.context_window = contextRule.context_window;

    models.push(model);
    seen[id] = true;
  }
  return models;
}

async function list(r) {
  if (!r.headersIn.Authorization) return send(r, 401, { error: "missing Authorization header" });

  try {
    const responses = await Promise.all([
      r.subrequest("/v1/models"),
      r.subrequest("/_aiapi_cpa_codex_catalog"),
    ]);
    const source = responses[0];
    const catalog = responses[1];
    if (source.status !== 200 || catalog.status !== 200) throw new Error("catalog request failed");

    return send(r, 200, {
      models: buildModels(
        JSON.parse(source.responseText),
        JSON.parse(catalog.responseText),
        cpaTransportRoutes(),
      ),
    });
  } catch (error) {
    r.error(`failed to build Codex model catalog: ${error.message}`);
    return send(r, 502, { error: "failed to build model catalog" });
  }
}

export default { list, cpaAuthorization };
