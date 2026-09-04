{{/*
ConfigMap data payloads, kept here rather than inline in each ConfigMap so the
workloads that mount them can hash the same bytes for their checksum/config
annotation.

Hash the data alone, never the rendered object, or chart-label churn rolls
every workload on every upgrade.

Each define emits the block that sits under `data:`, already indented, and
opens with a newline; callers write `data:{{ include ... }}` with no space.
Guards on whether the object exists at all stay with the ConfigMap templates
and their consumers.
*/}}

{{- define "thoras.monitorConfigData" }}
  config.yaml: |
{{ .Values.thorasMonitor.config | indent 4 }}
{{- end }}

{{- define "thoras.timescaleConfigData" }}
  custom.conf: |
{{ .Values.metricsCollector.timescale.config.content | indent 4 }}
{{- end }}

{{- define "thoras.dashboardOauth2ProxyTemplatesData" }}
  sign_in.html: |
{{ .Files.Get "files/oauth2-proxy-sign-in.html" | indent 4 }}
{{- end }}

{{- define "thoras.dashboardOauth2ProxyConfigData" -}}
{{- $auth := .Values.thorasDashboard.auth -}}
  {{- if eq $auth.mode "htpasswd" }}
  oauth2-proxy.cfg: |
    http_address = "0.0.0.0:{{ .Values.thorasDashboard.containerPort }}"
    upstreams = ["http://127.0.0.1:{{ include "thoras.dashboard.internalNginxPort" . }}"]
    # provider must be set; the dummy value below is unused by htpasswd auth.
    provider = "google"
    client_id = "thoras-dashboard"
    client_secret = "unused"
    email_domains = ["*"]
    htpasswd_file = "/etc/oauth2-proxy/generated/htpasswd"
    display_htpasswd_form = true
    # Do NOT set skip_provider_button=true - it bypasses the sign-in page
    # and calls the dummy provider, which 401s.
    cookie_secret_file = "/etc/oauth2-proxy/secret/cookie-secret"
    cookie_secure = {{ $auth.cookieSecure }}
    reverse_proxy = true
    silence_ping_logging = true
    banner = "Sign in to the Thoras Dashboard"
    custom_templates_dir = "/etc/oauth2-proxy/templates"
  {{- else if eq $auth.mode "oidc" }}
  oauth2-proxy.cfg: |
    http_address = "0.0.0.0:{{ .Values.thorasDashboard.containerPort }}"
    upstreams = ["http://127.0.0.1:{{ include "thoras.dashboard.internalNginxPort" . }}"]
    provider = {{ $auth.oidc.provider | quote }}
    oidc_issuer_url = {{ $auth.oidc.issuerURL | quote }}
    redirect_url = {{ $auth.oidc.redirectURL | quote }}
    client_secret_file = "/etc/oauth2-proxy/secret/client-secret"
    cookie_secret_file = "/etc/oauth2-proxy/secret/cookie-secret"
    email_domains = [{{ range $i, $d := $auth.oidc.emailDomains }}{{ if $i }}, {{ end }}{{ $d | quote }}{{ end }}]
    cookie_secure = {{ $auth.cookieSecure }}
    reverse_proxy = true
    silence_ping_logging = true
    skip_provider_button = {{ $auth.oidc.skipProviderButton }}
    insecure_oidc_allow_unverified_email = {{ $auth.oidc.insecureAllowUnverifiedEmail }}
    banner = "Sign in to the Thoras Dashboard"
    custom_templates_dir = "/etc/oauth2-proxy/templates"
  {{- end }}
{{- end }}

{{- define "thoras.dashboardNginxConfigData" }}
  nginx.conf.template: |
    pid /tmp/nginx.pid;

    events {
      worker_connections 1024;
    }

    http {
      client_body_temp_path /tmp/client_temp;
      proxy_temp_path       /tmp/proxy_temp;
      fastcgi_temp_path     /tmp/fastcgi_temp;
      uwsgi_temp_path       /tmp/uwsgi_temp;
      scgi_temp_path        /tmp/scgi_temp;

      include       /etc/nginx/mime.types;

      # Least-privilege allowlist for dashboard -> API calls.
      # Deny by default; only routes the dashboard actually uses are allowed.
      # New dashboard API calls require a matching entry here or they will 403.
      map $request_method$request_uri $thoras_dashboard_api_allowed {
        default 0;

        # GET — reads
        ~*^GET/v1/ast(\?|$)                                                       1;
        ~*^GET/v1/ast/[^/]+/[^/]+(\?|$)                                           1;
        ~*^GET/v1/ast/[^/]+/[^/]+/pods(\?|$)                                      1;
        ~*^GET/v1/ast/[^/]+/[^/]+/metrics/current(\?|$)                           1;
        ~*^GET/v1/ast/[^/]+/[^/]+/suggestions(\?|$)                               1;
        ~*^GET/v1/cost-savings/settings(\?|$)                                     1;
        ~*^GET/v1/export(\?|$)                                                    1;
        ~*^GET/v1/instance-costs/current(\?|$)                                    1;
        ~*^GET/v1/system/jobs/status(\?|$)                                        1;
        ~*^GET/v1/system/namespaces(\?|$)                                         1;
        ~*^GET/v1/system/status(\?|$)                                             1;
        ~*^GET/v1/views/asts(\?|$)                                                1;
        ~*^GET/v1/views/asts/[^/]+/[^/]+(\?|$)                                    1;
        ~*^GET/v1/views/cost/analysis(\?|$)                                       1;
        ~*^GET/v1/views/cost/details(\?|$)                                        1;
        ~*^GET/v1/views/cost/details/export(\?|$)                                 1;
        ~*^GET/v1/views/cost/details/namespaces/[^/]+(\?|$)                       1;
        ~*^GET/v1/views/cost/projected(\?|$)                                      1;
        ~*^GET/v1/views/cost/savings-summary(\?|$)                                1;
        ~*^GET/v1/views/cost/savings-summary/namespaces/[^/]+(\?|$)               1;
        ~*^GET/v1/views/kpis(\?|$)                                                1;
        ~*^GET/v1/views/labels(\?|$)                                              1;
        ~*^GET/v1/views/namespaces/[^/]+/asts(\?|$)                               1;
        ~*^GET/v1/views/namespaces/[^/]+/kpis(\?|$)                               1;
        ~*^GET/v1/views/namespaces/[^/]+/labels(\?|$)                             1;
        ~*^GET/v1/views/node-pools(\?|$)                                          1;
        ~*^GET/v1/views/nodes(\?|$)                                               1;
        ~*^GET/v1/views/nodes/summary(\?|$)                                       1;
        ~*^GET/v1/pods/[^/]+/[^/]+/logs(\?|$)                                     1;
        ~*^GET/v1/persistent-volumes(\?|$)                                        1;


        # POST — dashboard-initiated mutations
        ~*^POST/v1/ast/candidates/[^/]+(\?|$)                                     1;
        ~*^POST/v1/ast/enroll/all(\?|$)                                           1;
        ~*^POST/v1/cost-savings/settings(\?|$)                                    1;

        # POST — reads that pass a request body (query payloads, not mutations)
        ~*^POST/v1/ast/[^/]+/metrics/series(\?|$)                                 1;

        # PATCH — scale mode toggle
        ~*^PATCH/v1/ast/[^/]+/[^/]+/mode(\?|$)                                    1;

        # PUT — pause/resume system-wide scaling
        ~*^PUT/v1/system/scaling(\?|$)                                            1;
      }

      server {
        {{- if .Values.thorasDashboard.auth.enabled }}
        {{- $internalPort := include "thoras.dashboard.internalNginxPort" . }}
        # Loopback-only; oauth2-proxy sidecar fronts containerPort.
        listen       127.0.0.1:{{ $internalPort }};
        listen       [::1]:{{ $internalPort }} ipv6only=on;
        {{- else }}
        listen       {{ .Values.thorasDashboard.containerPort }};
        listen       [::]:{{ .Values.thorasDashboard.containerPort }} ipv6only=on;
        {{- end }}
        server_name  localhost;

        root   /usr/share/nginx/html;
        index  index.html index.htm;

        location /v1/ {
          if ($thoras_dashboard_api_allowed != 1) {
            return 403;
          }
          proxy_pass http://thoras-api-server-v2;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          {{- if eq (include "thoras.apiClientEnabled" .) "true" }}
          proxy_set_header Authorization "Bearer ${SIMPLE_AUTH_SECRET}";
          {{- end }}
        }

        location /config.json {
            default_type application/json;
            return 200 '{ "api_base_url": "", "version": "{{ .Chart.Version }}", "platformVersion": "{{ .Values.thorasVersion }}", "featureFlags": {"ignoreNewPods": {{ .Values.thorasForecast.ignoreNewPods }}, "enableUpdateScaleModeApi": {{ .Values.featureFlags.enableUpdateScaleModeApi }}, "enablePodLogStreaming": {{ .Values.featureFlags.enablePodLogStreaming | default false }}}, "extra": {{ toJson (merge (dict "cluster_name" .Values.cluster.name) .Values.thorasDashboard.extras) }} }';
        }

        location / {
          try_files $uri /index.html;
        }

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf|ttf|map)$ {
          expires 1y;
          access_log off;
          add_header Cache-Control "public";
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
          root   /usr/share/nginx/html;
        }
      }
    }
{{- end }}
