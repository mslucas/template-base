import React from "react";

const h = React.createElement;

export function Shell({ title, subtitle, children, actions }) {
  return h(
    "main",
    { className: "tpl-shell" },
    h(
      "header",
      { className: "tpl-header" },
      h(
        "div",
        null,
        h("h1", { className: "tpl-title" }, title),
        subtitle ? h("p", { className: "tpl-subtitle" }, subtitle) : null,
      ),
      actions ? h("div", { className: "tpl-actions" }, actions) : null,
    ),
    h("section", { className: "tpl-content" }, children),
  );
}

export function Panel({ title, children }) {
  return h(
    "article",
    { className: "tpl-panel" },
    title ? h("h2", { className: "tpl-panel-title" }, title) : null,
    children,
  );
}

export function KeyValue({ label, value }) {
  return h(
    "div",
    { className: "tpl-kv-row" },
    h("span", { className: "tpl-kv-label" }, label),
    h("code", { className: "tpl-kv-value" }, value),
  );
}

export function Button({ label, onClick, type = "button", variant = "primary", disabled = false }) {
  return h(
    "button",
    {
      className: `tpl-btn tpl-btn-${variant}`,
      onClick,
      type,
      disabled,
    },
    label,
  );
}
