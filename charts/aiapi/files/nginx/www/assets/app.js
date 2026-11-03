const origin = getSiteOrigin();
const docUrl = `${origin}/doc/`;
const platforms = [
  { id: "unix", label: "macOS / Linux / WSL / Git Bash" },
  { id: "windows", label: "Windows PowerShell" },
];
const clients = [
  {
    id: "codex",
    name: "Codex",
    protocol: "OpenAI Responses",
    description: "写入 provider、默认模型和 API Key，适合优先接入 Codex。",
  },
  {
    id: "claude-code",
    name: "Claude Code",
    protocol: "Anthropic Messages",
    description: "写入 Claude Code 环境配置，适合 Anthropic-compatible Agent 客户端。",
  },
];

function getSiteOrigin() {
  if (window.location.host) {
    return `${window.location.protocol}//${window.location.host}`;
  }

  return "https://<current-host>";
}

function getInstallCommand(clientId, platformId) {
  if (platformId === "windows") {
    return `irm "${origin}/getstart/${clientId}-windows" | iex`;
  }

  return `curl -fsSL "${origin}/getstart/${clientId}" | sh -s`;
}

function createTextNode(tagName, className, text) {
  const node = document.createElement(tagName);
  if (className) {
    node.className = className;
  }
  node.textContent = text;
  return node;
}

function renderClientCards() {
  const grid = document.querySelector("[data-client-grid]");
  if (!grid) {
    return;
  }

  clients.forEach((client) => {
    const article = document.createElement("article");
    article.className = "client-card";

    const head = document.createElement("div");
    head.className = "client-head";
    head.append(
      createTextNode("span", "", client.protocol),
      createTextNode("h3", "", client.name),
    );

    const description = createTextNode("p", "", client.description);
    const commandGroup = document.createElement("div");
    commandGroup.className = "command-group";

    platforms.forEach((platform) => {
      const block = document.createElement("div");
      block.className = "command-block";

      const label = createTextNode("span", "command-label", platform.label);
      const row = document.createElement("div");
      row.className = "code-row";

      const command = getInstallCommand(client.id, platform.id);
      const code = createTextNode("code", "command", command);
      const button = createTextNode("button", "copy", "复制");
      button.type = "button";
      button.dataset.copyCommand = command;

      row.append(code, button);
      block.append(label, row);
      commandGroup.append(block);
    });

    article.append(head, description, commandGroup);
    grid.append(article);
  });
}

renderClientCards();

document.querySelectorAll("[data-site-origin]").forEach((node) => {
  node.textContent = origin;
});

document.querySelectorAll("[data-site-doc-url]").forEach((node) => {
  node.textContent = docUrl;
});

document.querySelectorAll("[data-site-link]").forEach((node) => {
  node.setAttribute("href", `${origin}${node.dataset.siteLink}`);
});

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  document.body.appendChild(textarea);
  textarea.select();
  document.execCommand("copy");
  textarea.remove();
}

document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-command]");
  if (!button) {
    return;
  }

  await copyText(button.dataset.copyCommand);
  button.textContent = "已复制";
  button.classList.add("copied");

  window.setTimeout(() => {
    button.textContent = "复制";
    button.classList.remove("copied");
  }, 1600);
});
