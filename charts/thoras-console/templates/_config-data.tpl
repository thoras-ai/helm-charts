{{/*
ConfigMap data payloads, kept here rather than inline in the ConfigMap so the
workload that mounts one can hash the same bytes for its checksum/config
annotation.

Hash the data alone, never the rendered object, or chart-label churn rolls
every workload on every upgrade.

Each define emits the block that sits under `data:`, already indented, and
opens with a newline; callers write `data:{{ include ... }}` with no space.
*/}}

{{- define "thoras-console.dashboardNginxConfigData" }}
{{- $auth := .Values.consoleApi.auth }}
{{- $dashboard := .Values.consoleDashboard }}
{{- $oidcMode := or (eq $auth.mode "oidc") (eq $auth.mode "both") }}
{{- /* Mode and issuer mirror console-api: the dashboard has no way to ask the
       server which it is running, so the two must not drift. client_id is
       browser-only and has no server-side counterpart. */}}
{{- $consoleAuth := dict "mode" $auth.mode "scope" $dashboard.auth.scope }}
{{- if $oidcMode }}
{{- $_ := set $consoleAuth "issuer" $auth.oidc.issuer }}
{{- $_ := set $consoleAuth "client_id" $dashboard.auth.clientId }}
{{- /* console-api takes a comma-separated list; the browser sends exactly one. */}}
{{- $audience := $dashboard.auth.audience | default (first (splitList "," $auth.oidc.audiences)) | trim }}
{{- if $audience }}
{{- $_ := set $consoleAuth "audience" $audience }}
{{- end }}
{{- end }}
{{- $config := dict
      "api_base_url" ""
      "version" .Chart.Version
      "platformVersion" .Values.consoleVersion
      "console" (dict "auth" $consoleAuth)
      "extra" $dashboard.extras }}
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

      # Deny by default. ingest/ and hook/ are not dashboard routes and this
      # hostname is browser-facing; both reach console-api through its own
      # Ingress. nginx takes the first matching regex, so denials come first.
      map $request_uri $thoras_console_dashboard_api_allowed {
        default 0;

        ~*^/api/v1/ingest/    0;
        ~*^/api/v1/hook/      0;

        ~*^/api/v1/           1;
      }

      server {
        listen       {{ $dashboard.containerPort }};
        listen       [::]:{{ $dashboard.containerPort }} ipv6only=on;
        server_name  localhost;

        root   /usr/share/nginx/html;
        index  index.html index.htm;

        location /api/ {
          if ($thoras_console_dashboard_api_allowed != 1) {
            return 403;
          }
          proxy_pass http://thoras-console-api:{{ .Values.consoleApi.port }};
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        }

        {{- /* Shadows the developer config.json baked into the image. Lose this
               and the pod silently serves that one, pointed at localhost. */}}
        location /config.json {
            default_type application/json;
            return 200 '{{ toJson $config }}';
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
