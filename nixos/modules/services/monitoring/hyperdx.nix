{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkPackageOption
    types
    ;

  cfg = config.services.hyperdx;
  uiCfg = cfg.ui;
  otelCfg = cfg.opentelemetry-collector;

  uiDefaultConnection = {
    name = "Local ClickHouse";
    host = uiCfg.defaultClickHouse.host;
    username = uiCfg.defaultClickHouse.username;
    password = "";
  };

  uiDefaultSources = [
    {
      from = {
        databaseName = uiCfg.defaultClickHouse.database;
        tableName = "otel_logs";
      };
      kind = "log";
      timestampValueExpression = "Timestamp";
      name = "Logs";
      displayedTimestampValueExpression = "Timestamp";
      implicitColumnExpression = "Body";
      serviceNameExpression = "ServiceName";
      bodyExpression = "Body";
      eventAttributesExpression = "LogAttributes";
      resourceAttributesExpression = "ResourceAttributes";
      defaultTableSelectExpression = "Timestamp,ServiceName,SeverityText,Body";
      severityTextExpression = "SeverityText";
      traceIdExpression = "TraceId";
      spanIdExpression = "SpanId";
      metadataMaterializedViews = {
        keyRollupTable = "otel_logs_key_rollup_15m";
        kvRollupTable = "otel_logs_kv_rollup_15m";
        granularity = "15 minute";
      };
      connection = uiDefaultConnection.name;
      traceSourceId = "Traces";
      sessionSourceId = "Sessions";
      metricSourceId = "Metrics";
    }
    {
      from = {
        databaseName = uiCfg.defaultClickHouse.database;
        tableName = "otel_traces";
      };
      kind = "trace";
      timestampValueExpression = "Timestamp";
      name = "Traces";
      displayedTimestampValueExpression = "Timestamp";
      implicitColumnExpression = "SpanName";
      serviceNameExpression = "ServiceName";
      eventAttributesExpression = "SpanAttributes";
      resourceAttributesExpression = "ResourceAttributes";
      defaultTableSelectExpression = "Timestamp,ServiceName,StatusCode,round(Duration/1e6),SpanName";
      traceIdExpression = "TraceId";
      spanIdExpression = "SpanId";
      durationExpression = "Duration";
      durationPrecision = 9;
      parentSpanIdExpression = "ParentSpanId";
      spanNameExpression = "SpanName";
      spanKindExpression = "SpanKind";
      statusCodeExpression = "StatusCode";
      statusMessageExpression = "StatusMessage";
      metadataMaterializedViews = {
        keyRollupTable = "otel_traces_key_rollup_15m";
        kvRollupTable = "otel_traces_kv_rollup_15m";
        granularity = "15 minute";
      };
      connection = uiDefaultConnection.name;
      logSourceId = "Logs";
      sessionSourceId = "Sessions";
      metricSourceId = "Metrics";
    }
    {
      from = {
        databaseName = uiCfg.defaultClickHouse.database;
        tableName = "";
      };
      kind = "metric";
      timestampValueExpression = "TimeUnix";
      name = "Metrics";
      resourceAttributesExpression = "ResourceAttributes";
      metricTables = {
        gauge = "otel_metrics_gauge";
        histogram = "otel_metrics_histogram";
        sum = "otel_metrics_sum";
      };
      connection = uiDefaultConnection.name;
      logSourceId = "Logs";
      traceSourceId = "Traces";
      sessionSourceId = "Sessions";
    }
    {
      from = {
        databaseName = uiCfg.defaultClickHouse.database;
        tableName = "hyperdx_sessions";
      };
      kind = "session";
      timestampValueExpression = "TimestampTime";
      name = "Sessions";
      displayedTimestampValueExpression = "Timestamp";
      implicitColumnExpression = "Body";
      serviceNameExpression = "ServiceName";
      bodyExpression = "Body";
      eventAttributesExpression = "LogAttributes";
      resourceAttributesExpression = "ResourceAttributes";
      defaultTableSelectExpression = "Timestamp,ServiceName,SeverityText,Body";
      severityTextExpression = "SeverityText";
      traceIdExpression = "TraceId";
      spanIdExpression = "SpanId";
      connection = uiDefaultConnection.name;
      logSourceId = "Logs";
      traceSourceId = "Traces";
      metricSourceId = "Metrics";
    }
  ];

  uiDefaultEnvironment = {
    FRONTEND_URL = "${uiCfg.appUrl}:${toString uiCfg.appPort}";
    HYPERDX_API_PORT = toString uiCfg.apiPort;
    HYPERDX_APP_LISTEN_HOSTNAME = uiCfg.listenHost;
    HYPERDX_APP_PORT = toString uiCfg.appPort;
    HYPERDX_APP_URL = uiCfg.appUrl;
    HYPERDX_LOG_LEVEL = "info";
    HYPERDX_OPAMP_PORT = toString uiCfg.opampPort;
    MONGO_URI = uiCfg.mongoUri;
    NODE_ENV = "production";
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://127.0.0.1:4318";
    OTEL_SERVICE_NAME = "hdx-oss-app";
    SERVER_URL = "http://127.0.0.1:${toString uiCfg.apiPort}";
  }
  // lib.optionalAttrs uiCfg.provisionDefaultSources {
    DEFAULT_SOURCES = builtins.toJSON uiDefaultSources;
  }
  //
    lib.optionalAttrs (uiCfg.provisionDefaultSources && uiCfg.defaultClickHouse.passwordFile == null)
      {
        DEFAULT_CONNECTIONS = builtins.toJSON [ uiDefaultConnection ];
      };

  otelDefaultEnvironment = {
    CLICKHOUSE_ENDPOINT = "tcp://localhost:9000?dial_timeout=10s";
    CLICKHOUSE_PROMETHEUS_METRICS_ENDPOINT = "localhost:9363";
    CLICKHOUSE_USER = "default";
    CLICKHOUSE_PASSWORD = "";
    HYPERDX_LOG_LEVEL = "info";
    HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE = "default";
  };

  otelConfigFiles = [
    "${otelCfg.package}/share/otelcol-contrib/config.yaml"
    "${otelCfg.package}/share/otelcol-contrib/standalone-config.yaml"
  ]
  ++ otelCfg.extraConfigFiles;

in
{
  options.services.hyperdx = {
    ui = {
      enable = mkEnableOption ''
        HyperDX app/api service.
      '';

      package = mkPackageOption pkgs "hyperdx" { };

      listenHost = mkOption {
        type = types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = ''
          Address for the HyperDX NextJS app to listen on.
        '';
      };

      appPort = mkOption {
        type = types.port;
        default = 8080;
        description = ''
          Port for the HyperDX app service.
        '';
      };

      apiPort = mkOption {
        type = types.port;
        default = 8000;
        description = ''
          Port for the HyperDX API service.
        '';
      };

      opampPort = mkOption {
        type = types.port;
        default = 4320;
        description = ''
          Port for the HyperDX OpAMP API service.
        '';
      };

      appUrl = mkOption {
        type = types.str;
        default = "http://localhost";
        example = "https://hyperdx.example.com";
        description = ''
          Public URL, without the port, for the HyperDX app.
        '';
      };

      mongoUri = mkOption {
        type = types.str;
        default = "mongodb://127.0.0.1:27017/hyperdx";
        example = "mongodb://mongodb.example.com:27017/hyperdx";
        description = ''
          MongoDB connection string used for HyperDX metadata.
        '';
      };

      enableLocalMongoDB = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable the local MongoDB service for HyperDX metadata.
        '';
      };

      provisionDefaultSources = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to provision the default ClickHouse connection and OpenTelemetry sources
          when the first HyperDX team is registered.
        '';
      };

      defaultClickHouse = {
        host = mkOption {
          type = types.str;
          default = "http://127.0.0.1:8123";
          example = "http://clickhouse.example.com:8123";
          description = ''
            ClickHouse HTTP endpoint to use for the provisioned default connection.
          '';
        };

        username = mkOption {
          type = types.str;
          default = "default";
          description = ''
            ClickHouse user to use for the provisioned default connection.
          '';
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/secrets/hyperdx-clickhouse-password";
          description = ''
            File containing the ClickHouse password to use for the provisioned
            default connection. The file is passed to the service with systemd
            credentials and read at runtime.
          '';
        };

        database = mkOption {
          type = types.str;
          default = "default";
          description = ''
            ClickHouse database to use for the provisioned default sources.
          '';
        };
      };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          HYPERDX_LOG_LEVEL = "debug";
          USAGE_STATS_ENABLED = "false";
        };
        description = ''
          Environment variables passed to the HyperDX app/API service.
          These override the module's defaults.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to open the app, API, and OpAMP ports in the firewall.
        '';
      };
    };

    opentelemetry-collector = {
      enable = mkEnableOption ''
        HyperDX opentelemetry-collector service.
      '';

      package = mkPackageOption pkgs "hyperdx-otel-collector" { };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          CLICKHOUSE_ENDPOINT = "tcp://clickhouse.example.com:9000?dial_timeout=10s";
          HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE = "hyperdx";
        };
        description = ''
          Environment variables passed to the HyperDX OpenTelemetry collector.
          These override the module's defaults.
        '';
      };

      clickhousePasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/secrets/hyperdx-clickhouse-password";
        description = ''
          File containing the password for the ClickHouse user. The file is
          passed to the service with systemd credentials and read at runtime.

          Leave this unset when using the default local ClickHouse instance
          without a password.
        '';
      };

      extraConfigFiles = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = ''
          Extra OpenTelemetry collector configuration files to merge after the
          packaged HyperDX standalone configuration.
        '';
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Extra command line arguments passed to the collector.
        '';
      };

      runMigrations = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to run HyperDX's ClickHouse schema migration tool before
          starting the collector.
        '';
      };

      openFirewall = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to open the OTLP gRPC and HTTP receiver ports in the firewall.
        '';
      };
    };

    clickhouse = {
      enable = mkEnableOption ''
        local clickhouse DB with HyperDX configs.
      '';
    };
  };

  config = mkMerge [
    (mkIf cfg.ui.enable {
      services.mongodb = {
        enable = mkIf uiCfg.enableLocalMongoDB (lib.mkDefault true);

        # TODO(phlip9): upstream is using mongodb 5.0
        package = pkgs.mongodb-ce;
      };

      systemd.services.hyperdx = {
        description = "HyperDX app and API";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "network.target"
        ]
        ++ lib.optional uiCfg.enableLocalMongoDB "mongodb.service"
        ++ lib.optional config.services.clickhouse.enable "clickhouse.service"
        ++ lib.optional otelCfg.enable "hyperdx-opentelemetry-collector.service";
        after = [
          "network.target"
        ]
        ++ lib.optional uiCfg.enableLocalMongoDB "mongodb.service"
        ++ lib.optional config.services.clickhouse.enable "clickhouse.service"
        ++ lib.optional otelCfg.enable "hyperdx-opentelemetry-collector.service";

        environment = uiDefaultEnvironment // uiCfg.environment;

        serviceConfig = {
          ExecStart = pkgs.writeShellScript "hyperdx" ''
            ${lib.optionalString (uiCfg.defaultClickHouse.passwordFile != null) ''
              export CLICKHOUSE_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/clickhouse-password")"
            ''}
            ${lib.optionalString
              (
                uiCfg.provisionDefaultSources
                && uiCfg.defaultClickHouse.passwordFile != null
                && !(uiCfg.environment ? DEFAULT_CONNECTIONS)
              )
              ''
                export DEFAULT_CONNECTIONS="$(
                  ${getExe pkgs.jq} --compact-output --null-input \
                    --arg name ${lib.escapeShellArg uiDefaultConnection.name} \
                    --arg host ${lib.escapeShellArg uiDefaultConnection.host} \
                    --arg username ${lib.escapeShellArg uiDefaultConnection.username} \
                    --arg password "$CLICKHOUSE_PASSWORD" \
                    '[{ name: $name, host: $host, username: $username, password: $password }]'
                )"
              ''
            }
            exec ${getExe uiCfg.package}
          '';
          LoadCredential = lib.optional (
            uiCfg.defaultClickHouse.passwordFile != null
          ) "clickhouse-password:${uiCfg.defaultClickHouse.passwordFile}";
          DynamicUser = true;
          Restart = "always";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          DevicePolicy = "closed";
          NoNewPrivileges = true;
          StateDirectory = "hyperdx";
        };
      };

      networking.firewall.allowedTCPPorts = mkIf uiCfg.openFirewall [
        uiCfg.appPort
        uiCfg.apiPort
        uiCfg.opampPort
      ];
    })

    (mkIf otelCfg.enable {
      systemd.services.hyperdx-opentelemetry-collector = {
        description = "HyperDX OpenTelemetry Collector";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "network.target"
        ]
        ++ lib.optional config.services.clickhouse.enable "clickhouse.service";
        after = [
          "network.target"
        ]
        ++ lib.optional config.services.clickhouse.enable "clickhouse.service";

        environment = otelDefaultEnvironment // otelCfg.environment;

        serviceConfig = {
          ExecStartPre = lib.optionals otelCfg.runMigrations [
            (pkgs.writeShellScript "hyperdx-migrate" ''
              ${lib.optionalString (otelCfg.clickhousePasswordFile != null) ''
                export CLICKHOUSE_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/clickhouse-password")"
              ''}
              exec ${otelCfg.package}/bin/migrate ${otelCfg.package}/share/otel/schema/seed
            '')
          ];
          ExecStart = pkgs.writeShellScript "hyperdx-opentelemetry-collector" ''
            ${lib.optionalString (otelCfg.clickhousePasswordFile != null) ''
              export CLICKHOUSE_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/clickhouse-password")"
            ''}
            exec ${
              lib.escapeShellArgs (
                [ (getExe otelCfg.package) ]
                ++ map (configFile: "--config=file:${configFile}") otelConfigFiles
                ++ otelCfg.extraArgs
              )
            }
          '';
          LoadCredential = lib.optional (
            otelCfg.clickhousePasswordFile != null
          ) "clickhouse-password:${otelCfg.clickhousePasswordFile}";
          DynamicUser = true;
          Restart = "always";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          DevicePolicy = "closed";
          NoNewPrivileges = true;
          WorkingDirectory = "%S/hyperdx-opentelemetry-collector";
          StateDirectory = "hyperdx-opentelemetry-collector";
        };
      };

      networking.firewall.allowedTCPPorts = mkIf otelCfg.openFirewall [
        4317
        4318
      ];
    })

    (mkIf cfg.clickhouse.enable {
      services.clickhouse = {
        enable = true;

        # See: <https://github.com/hyperdxio/hyperdx/blob/main/docker/clickhouse/local/config.xml>
        serverConfig = {
          logger = {
            level = "debug";
            console = true;
            log."@remove" = "remove";
            errorlog."@remove" = "remove";
          };

          # TODO(phlip9)
          # <interserver_http_host>ch-server</interserver_http_host>
          # <interserver_http_port>9009</interserver_http_port>

          max_connections = 4096;
          keep_alive_timeout = 64;
          max_concurrent_queries = 100;
          uncompressed_cache_size = 8589934592;
          mark_cache_size = 5368709120;

          timezone = "UTC";
          mlock_executable = false;

          # Prometheus metrics exporter + remote write/read ingestion
          prometheus = {
            port = 9363;
            metrics = true;
            events = true;
            asynchronous_metrics = true;
            errors = true;
            handlers = {
              metrics_handler = {
                url = "/metrics";
                handler = {
                  type = "expose_metrics";
                  metrics = true;
                  asynchronous_metrics = true;
                  events = true;
                  errors = true;
                };
              };
              remote_write_handler = {
                url = "/write";
                handler = {
                  type = "remote_write";
                  database = "default";
                  table = "otel_metrics_ts";
                };
              };
              remote_read_handler = {
                url = "/read";
                handler = {
                  type = "remote_read";
                  database = "default";
                  table = "otel_metrics_ts";
                };
              };
            };
          };

          opentelemetry_span_log = {
            # The default table creation code is insufficient, this <engine> spec
            # is a workaround. There is no 'event_time' for this log, but two times,
            # start and finish. It is sorted by finish time, to avoid inserting
            # data too far away in the past (probably we can sometimes insert a span
            # that is seconds earlier than the last span in the table, due to a race
            # between several spans inserted in parallel). This gives the spans a
            # global order that we can use to e.g. retry insertion into some external
            # system.
            engine = ''
              engine MergeTree
              partition by toYYYYMM(finish_date)
              order by (finish_date, finish_time_us, trace_id)
            '';
          };

          # TODO(phlip9)
          # <remote_servers>
          #     <hdx_cluster>
          #         <shard>
          #             <replica>
          #                 <host>ch-server</host>
          #                 <port>9000</port>
          #             </replica>
          #         </shard>
          #     </hdx_cluster>
          # </remote_servers>

          custom_settings_prefixes = "hyperdx";
        };
      };
    })
  ];
}
