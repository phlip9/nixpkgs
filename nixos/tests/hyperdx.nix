{
  lib,
  pkgs,
  ...
}:
let
  clickhousePassword = "hyperdx-test-password";
  clickhousePasswordFile = pkgs.writeText "hyperdx-clickhouse-password" clickhousePassword;
in
{
  name = "hyperdx";
  meta.maintainers = with lib.maintainers; [ phlip9 ];

  containers.machine =
    {
      pkgs,
      ...
    }:
    {
      services.hyperdx.clickhouse.enable = true;
      services.hyperdx.ui = {
        enable = true;
        defaultClickHouse.passwordFile = clickhousePasswordFile;
        environment = {
          HYPERDX_LOG_LEVEL = "debug";
          USAGE_STATS_ENABLED = "false";
        };
        # TODO(phlip9): remove
        listenHost = "0.0.0.0";
        appUrl = "http://192.168.1.1";
      };
      services.hyperdx.opentelemetry-collector = {
        enable = true;
        inherit clickhousePasswordFile;
        environment.HYPERDX_OTEL_BATCH_TIMEOUT = "100ms";
      };

      services.clickhouse.usersConfig.users.default = {
        password."@remove" = "remove";
        password_sha256_hex = "52dde32448c3c62b2f097ace6e4b01c538c6193b2d10194340c7879771d03edd";
      };

      environment.systemPackages = with pkgs; [
        curl
        mongosh
      ];

      # TODO(phlip9): remove
      networking.firewall.allowedTCPPorts = [ 8080 ];

      # test@test.com : t3stTe$ttest

      # virtualisation.memorySize = 4096;
    };

  testScript = ''
    import json
    import shlex
    import time
    from uuid import uuid4

    machine.start()

    machine.wait_for_unit("clickhouse.service")
    machine.wait_for_open_port(9000)
    machine.wait_for_open_port(9363)
    machine.wait_for_unit("mongodb.service")
    machine.wait_for_open_port(27017)

    machine.wait_for_unit("hyperdx-opentelemetry-collector.service")
    machine.wait_for_open_port(4317)
    machine.wait_for_open_port(4318)
    machine.wait_for_open_port(13133)
    machine.wait_until_succeeds("curl --fail http://localhost:13133/")

    machine.succeed("grep -qF 'LoadCredential=clickhouse-password:${clickhousePasswordFile}' /etc/systemd/system/hyperdx-opentelemetry-collector.service")
    machine.fail("grep -qF '${clickhousePassword}' /etc/systemd/system/hyperdx-opentelemetry-collector.service")

    machine.wait_for_unit("hyperdx.service")
    machine.wait_for_open_port(8000)
    machine.wait_for_open_port(8080)
    machine.wait_for_open_port(4320)
    machine.wait_until_succeeds("curl --fail http://localhost:8000/health | grep OK")
    machine.wait_until_succeeds("curl --fail http://localhost:8080/api/health | grep OK")
    machine.wait_until_succeeds("curl --fail http://localhost:4320/health | grep OK")

    machine.succeed("grep -qF 'LoadCredential=clickhouse-password:${clickhousePasswordFile}' /etc/systemd/system/hyperdx.service")
    machine.fail("grep -qF '${clickhousePassword}' /etc/systemd/system/hyperdx.service")

    machine.succeed(
        "clickhouse-client --password '${clickhousePassword}' --query 'EXISTS TABLE default.otel_logs' | grep 1"
    )

    machine.succeed(
        "curl --fail http://localhost:8080/api/installation | grep '\"isTeamExisting\":false'"
    )

    machine.succeed(
        "curl --fail --cookie-jar /tmp/hyperdx.cookies --cookie /tmp/hyperdx.cookies "
        "-X POST http://localhost:8080/api/register/password "
        "-H 'Content-Type: application/json' "
        "--data '{\"email\":\"nixos@example.com\",\"password\":\"HyperdxTest123!\",\"confirmPassword\":\"HyperdxTest123!\"}' "
        "| grep '\"status\":\"success\"'"
    )

    machine.wait_until_succeeds(
        "curl --fail --cookie /tmp/hyperdx.cookies http://localhost:8080/api/connections "
        "| grep 'Local ClickHouse'",
        timeout=10,
    )
    machine.wait_until_succeeds(
        "curl --fail --cookie /tmp/hyperdx.cookies http://localhost:8080/api/sources "
        "| grep '\"name\":\"Logs\"' "
        "&& curl --fail --cookie /tmp/hyperdx.cookies http://localhost:8080/api/sources "
        "| grep '\"name\":\"Traces\"' "
        "&& curl --fail --cookie /tmp/hyperdx.cookies http://localhost:8080/api/sources "
        "| grep '\"name\":\"Metrics\"'",
        timeout=10,
    )
    machine.succeed(
        "mongosh mongodb://127.0.0.1:27017/hyperdx --quiet "
        "--eval 'print(db.connections.findOne({name: \"Local ClickHouse\"}).password)' "
        "| grep '${clickhousePassword}'"
    )

    flag = f"hyperdx-nixos-test-{uuid4()}"
    event = {
        "resourceLogs": [
            {
                "resource": {
                    "attributes": [
                        {
                            "key": "service.name",
                            "value": {"stringValue": "hyperdx-nixos-test"},
                        },
                    ],
                },
                "scopeLogs": [
                    {
                        "logRecords": [
                            {
                                "timeUnixNano": str(time.time_ns()),
                                "severityNumber": 9,
                                "severityText": "Info",
                                "body": {"stringValue": flag},
                                "attributes": [],
                            },
                        ],
                    },
                ],
            },
        ],
    }

    machine.succeed(
        "curl --fail -X POST http://localhost:4318/v1/logs "
        "-H 'Content-Type: application/json' "
        f"--data-binary {shlex.quote(json.dumps(event))}"
    )

    machine.wait_until_succeeds(
        f"clickhouse-client --password '${clickhousePassword}' --query "
        f"\"SELECT Body FROM default.otel_logs WHERE Body = '{flag}' FORMAT TSV\" "
        f"| grep {flag}",
        timeout=10,
    )
  '';
}
