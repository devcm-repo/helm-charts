import fs from "fs";

const cpaConfigPath = "/run/secrets/cliproxyapi-config.yaml";
const DIRECT_COMPAT_PROFILE = {
  tool_mode: "code_mode_only",
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

function extractFirstListScalar(lines, startIndex, listIndent) {
  for (let i = startIndex; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const indent = (line.match(/^\s*/) || [""])[0].length;
    const item = line.match(/^\s*-\s*(.*?)\s*$/);
    if (item && indent >= listIndent) {
      const value = yamlScalar(item[1]);
      return value ? "Bearer " + value : "";
    }
    if (indent <= listIndent) break;
    // Child mapping under api-keys: (e.g. CPA v8 provider map), not a key list.
    break;
  }
  return "";
}

export function cpaAuthorizationFromConfig(config) {
  const lines = typeof config === "string" ? config.split(/\r?\n/) : [];
  let inAccess = false;
  let legacyFallback = "";

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const indent = (line.match(/^\s*/) || [""])[0].length;

    if (indent === 0) {
      const top = line.match(/^([a-z0-9-]+)\s*:\s*(?:#.*)?$/i);
      inAccess = Boolean(top && top[1] === "access");
      if (top && top[1] === "api-keys" && !legacyFallback) {
        legacyFallback = extractFirstListScalar(lines, i + 1, 0);
      }
      continue;
    }

    if (inAccess) {
      const key = line.match(/^(\s*)api-keys\s*:\s*(?:#.*)?$/);
      if (key) {
        const found = extractFirstListScalar(lines, i + 1, key[1].length);
        if (found) return found;
      }
    }
  }
  return legacyFallback;
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
  if (
    section === "codex-api-key" ||
    section === "xai-api-key" ||
    section === "codex" ||
    section === "xai"
  ) {
    return { kind: "direct_compat", protocol: "third_party_responses" };
  }
  return null;
}

export function cpaTransportRoutesFromConfig(config) {
  const routes = {};
  const lines = typeof config === "string" ? config.split(/\r?\n/) : [];
  let inApiKeysBlock = false;
  let apiKeysChildIndent = -1;
  let section = "";
  let sectionIndent = -1;
  let modelsIndent = -1;
  let itemIndent = -1;
  let fieldIndent = -1;
  let model = null;

  const commit = () => {
    if (!model || !model.name) return;
    const id = model.alias || model.name;
    const next = routeForSection(section);
    const current = routes[id];
    if (!current || next.protocol === "third_party_responses") routes[id] = next;
    model = null;
  };

  const resetModels = () => {
    commit();
    modelsIndent = -1;
    itemIndent = -1;
    fieldIndent = -1;
  };

  for (const line of lines) {
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const indent = (line.match(/^\s*/) || [""])[0].length;

    if (indent === 0) {
      resetModels();
      const top = line.match(/^([a-z0-9-]+)\s*:/i);
      if (top && top[1] === "api-keys") {
        inApiKeysBlock = true;
        apiKeysChildIndent = -1;
        section = "";
        sectionIndent = -1;
      } else if (top && routeForSection(top[1])) {
        inApiKeysBlock = false;
        apiKeysChildIndent = -1;
        section = top[1];
        sectionIndent = 0;
      } else {
        inApiKeysBlock = false;
        apiKeysChildIndent = -1;
        section = "";
        sectionIndent = -1;
      }
      continue;
    }

    if (inApiKeysBlock) {
      if (apiKeysChildIndent < 0) {
        if (/^\s*-/.test(line)) {
          // Legacy v7 top-level api-keys list, not a v8 provider map.
          inApiKeysBlock = false;
          continue;
        }
        apiKeysChildIndent = indent;
      }
      if (indent === apiKeysChildIndent && !/^\s*-/.test(line)) {
        resetModels();
        const sub = line.match(/^\s*([a-z0-9-]+)\s*:/i);
        if (sub && routeForSection(sub[1])) {
          section = sub[1];
          sectionIndent = indent;
        } else {
          section = "";
          sectionIndent = -1;
        }
        continue;
      }
    }

    if (!section) continue;

    if (modelsIndent >= 0) {
      if (indent < modelsIndent || (indent === modelsIndent && !/^\s*-/.test(line))) {
        resetModels();
      } else {
        const dash = line.match(/^(\s*-\s*)(.*)$/);
        if (dash && (itemIndent < 0 || indent === itemIndent)) {
          commit();
          itemIndent = indent;
          fieldIndent = dash[1].length;
          model = { name: "", alias: "" };
          const inlineName = dash[2].match(/^name\s*:\s*(.*?)\s*$/);
          const inlineAlias = dash[2].match(/^alias\s*:\s*(.*?)\s*$/);
          if (inlineName) model.name = yamlScalar(inlineName[1]);
          if (inlineAlias) model.alias = yamlScalar(inlineAlias[1]);
          continue;
        }
        if (model && indent === fieldIndent) {
          const name = line.match(/^\s*name\s*:\s*(.*?)\s*$/);
          if (name) {
            model.name = yamlScalar(name[1]);
            continue;
          }
          const alias = line.match(/^\s*alias\s*:\s*(.*?)\s*$/);
          if (alias) {
            model.alias = yamlScalar(alias[1]);
            continue;
          }
        }
        continue;
      }
    }

    const models = line.match(/^\s*models\s*:\s*(?:#.*)?$/);
    if (models && indent > sectionIndent) {
      resetModels();
      modelsIndent = indent;
    }
  }
  resetModels();
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
    if (model.visibility === "list") model.supported_in_api = true;

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
