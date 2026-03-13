import React from "react";
import { createRoot } from "react-dom/client";
import { Button, KeyValue, Panel, Shell } from "../design-system/components.js";
import {
  fetchPlatformMeta,
  fetchSecureTemplateData,
  probeWebSocket,
} from "../shared/platform-client.js";
import {
  getActiveSession,
  getAuthenticatedUser,
  handleLoginCallback,
  logoutFromKeycloak,
  startLoginFlow,
} from "../shared/auth-client.js";

const h = React.createElement;

function AdminApp() {
  const [authState, setAuthState] = React.useState({
    loading: true,
    authenticated: false,
    user: null,
    error: "",
  });
  const [metaState, setMetaState] = React.useState({ loading: true, data: null, error: "" });
  const [wsState, setWsState] = React.useState({ loading: true, data: null, error: "" });
  const [secureState, setSecureState] = React.useState({ loading: false, data: null, error: "" });

  React.useEffect(() => {
    let alive = true;

    (async () => {
      try {
        await handleLoginCallback({ appKind: "admin" });
        const user = getAuthenticatedUser({ appKind: "admin" });
        if (!alive) {
          return;
        }
        setAuthState({ loading: false, authenticated: Boolean(user), user, error: "" });
      } catch (error) {
        if (!alive) {
          return;
        }
        setAuthState({
          loading: false,
          authenticated: false,
          user: null,
          error: error.message || "falha no login SSO",
        });
      }
    })();

    return () => {
      alive = false;
    };
  }, []);

  React.useEffect(() => {
    let alive = true;
    const controller = new AbortController();

    fetchPlatformMeta({ signal: controller.signal })
      .then((result) => {
        if (!alive) {
          return;
        }
        setMetaState({ loading: false, data: result, error: "" });
      })
      .catch((error) => {
        if (!alive) {
          return;
        }
        setMetaState({ loading: false, data: null, error: error.message || "meta indisponivel" });
      });

    probeWebSocket()
      .then((result) => {
        if (!alive) {
          return;
        }
        setWsState({ loading: false, data: result, error: "" });
      })
      .catch((error) => {
        if (!alive) {
          return;
        }
        setWsState({ loading: false, data: null, error: error.message || "ws indisponivel" });
      });

    return () => {
      alive = false;
      controller.abort();
    };
  }, []);

  React.useEffect(() => {
    let alive = true;
    const session = getActiveSession({ appKind: "admin" });
    if (!session?.access_token) {
      setSecureState({ loading: false, data: null, error: "" });
      return undefined;
    }

    const controller = new AbortController();
    setSecureState({ loading: true, data: null, error: "" });
    fetchSecureTemplateData({
      accessToken: session.access_token,
      signal: controller.signal,
    })
      .then((payload) => {
        if (!alive) {
          return;
        }
        setSecureState({ loading: false, data: payload, error: "" });
      })
      .catch((error) => {
        if (!alive) {
          return;
        }
        setSecureState({ loading: false, data: null, error: error.message || "falha em endpoint protegido" });
      });

    return () => {
      alive = false;
      controller.abort();
    };
  }, [authState.authenticated]);

  return h(
    Shell,
    {
      title: "Template Admin",
      subtitle: "Backoffice tecnico inicial para operacao da plataforma",
      actions: authState.authenticated
        ? h(Button, { label: "Sair", variant: "secondary", onClick: () => logoutFromKeycloak({ appKind: "admin" }) })
        : h(Button, {
            label: "Entrar com SSO",
            onClick: () => startLoginFlow({ appKind: "admin" }).catch((error) => {
              setAuthState((current) => ({ ...current, error: error.message || "falha no login" }));
            }),
          }),
    },
    h(
      "div",
      { className: "tpl-grid" },
      h(
        Panel,
        { title: "Sessao SSO" },
        authState.loading
          ? h("p", { className: "tpl-note" }, "Carregando estado de autenticacao...")
          : h(
              React.Fragment,
              null,
              h(KeyValue, { label: "Autenticado", value: authState.authenticated ? "sim" : "nao" }),
              h(KeyValue, { label: "Usuario", value: authState.user?.username || "-" }),
              h(KeyValue, { label: "Roles", value: (authState.user?.roles || []).join(", ") || "-" }),
              authState.error ? h("p", { className: "tpl-note" }, `Erro: ${authState.error}`) : null,
            ),
      ),
      h(
        Panel,
        { title: "API Gateway /meta" },
        metaState.loading
          ? h("p", { className: "tpl-note" }, "Consultando /api/v1/platform/meta...")
          : h(
              React.Fragment,
              null,
              h(KeyValue, { label: "Base URL", value: metaState.data?.baseUrl || "-" }),
              h(KeyValue, { label: "Service", value: metaState.data?.payload?.service || "-" }),
              h(KeyValue, { label: "Version", value: metaState.data?.payload?.version || "-" }),
              h(KeyValue, { label: "Runtime", value: metaState.data?.payload?.runtime || "-" }),
              metaState.error ? h("p", { className: "tpl-note" }, `Erro: ${metaState.error}`) : null,
            ),
      ),
      h(
        Panel,
        { title: "WebSocket /ws" },
        wsState.loading
          ? h("p", { className: "tpl-note" }, "Testando conexao websocket...")
          : h(
              React.Fragment,
              null,
              h(KeyValue, { label: "URL", value: wsState.data?.wsUrl || "-" }),
              h(KeyValue, { label: "Latencia", value: wsState.data ? `${wsState.data.latencyMs} ms` : "-" }),
              wsState.error ? h("p", { className: "tpl-note" }, `Erro: ${wsState.error}`) : null,
            ),
      ),
      h(
        Panel,
        { title: "Endpoint protegido" },
        secureState.loading
          ? h("p", { className: "tpl-note" }, "Validando token em /api/v1/template/secure...")
          : h(
              React.Fragment,
              null,
              h(KeyValue, {
                label: "Resultado",
                value: secureState.data?.status || (authState.authenticated ? "sem resposta" : "login necessario"),
              }),
              h(KeyValue, {
                label: "Principal",
                value: secureState.data?.principal || "-",
              }),
              secureState.error ? h("p", { className: "tpl-note" }, `Erro: ${secureState.error}`) : null,
            ),
      ),
    ),
  );
}

createRoot(document.getElementById("root")).render(h(AdminApp));
