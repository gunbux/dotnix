# Sprint dashboard for Grafana, read from the `sprint` CLI's SQLite log.
# Views (item_state, pr_state, goal_current, progress, burnup) live in
# pkgs/sprint/sprint.py, so the SQL here stays short.
let
  ds = {
    type = "frser-sqlite-datasource";
    uid = "sprint-sqlite";
  };
  sid = "(SELECT id FROM sprints WHERE slug = '$sprint')";
  local = col: "datetime(${col}, 'unixepoch', 'localtime')";

  target = queryType: sql: {
    refId = "A";
    datasource = ds;
    inherit queryType;
    rawQueryText = sql;
    queryText = sql;
    timeColumns =
      if queryType == "time series"
      then ["time"]
      else [];
  };

  panel = id: title: type: gridPos: queryType: sql: extra:
    {
      inherit id title type gridPos;
      datasource = ds;
      targets = [(target queryType sql)];
    }
    // extra;

  textStat = {
    options = {
      reduceOptions = {
        values = true;
        calcs = ["lastNotNull"];
        fields = "/.*/";
      };
      textMode = "value";
      colorMode = "none";
      graphMode = "none";
      justifyMode = "center";
    };
  };

  statusColors = {
    type = "value";
    options = {
      planned = {
        text = "planned";
        color = "text";
      };
      doing = {
        text = "doing";
        color = "blue";
      };
      blocked = {
        text = "blocked";
        color = "orange";
      };
      done = {
        text = "done";
        color = "green";
      };
      dropped = {
        text = "dropped";
        color = "#808080";
      };
      opened = {
        text = "opened";
        color = "blue";
      };
      ready = {
        text = "ready (5/5)";
        color = "purple";
      };
      merged = {
        text = "merged";
        color = "green";
      };
      closed = {
        text = "closed";
        color = "#808080";
      };
    };
  };

  colorText = name: {
    matcher = {
      id = "byName";
      options = name;
    };
    properties = [
      {
        id = "mappings";
        value = [statusColors];
      }
      {
        id = "custom.cellOptions";
        value = {type = "color-text";};
      }
    ];
  };

  linkColumn = name: {
    matcher = {
      id = "byName";
      options = name;
    };
    properties = [
      {
        id = "links";
        value = [
          {
            title = "Open";
            url = "\${__value.text}";
            targetBlank = true;
          }
        ];
      }
    ];
  };

  width = name: px: {
    matcher = {
      id = "byName";
      options = name;
    };
    properties = [
      {
        id = "custom.width";
        value = px;
      }
    ];
  };

  line = {
    custom = {
      lineWidth = 2;
      fillOpacity = 0;
      showPoints = "always";
      pointSize = 6;
      spanNulls = true;
    };
    decimals = 0;
    min = 0;
  };
in {
  uid = "sprint";
  title = "Sprint";
  tags = ["sprint"];
  editable = false;
  refresh = "30s";
  schemaVersion = 39;
  time = {
    from = "now-7d";
    to = "now";
  };

  templating.list = [
    {
      name = "sprint";
      label = "Sprint";
      type = "query";
      datasource = ds;
      query = "SELECT slug FROM sprints ORDER BY started_at DESC";
      refresh = 1;
      sort = 0;
    }
  ];

  annotations.list = [
    {
      name = "Goal changes";
      enable = true;
      iconColor = "orange";
      datasource = ds;
      # Table mode, with `time` converted to a timestamp for the annotation.
      target =
        target "table" ''
          SELECT g.at AS time,
                 'Goal v' || (SELECT COUNT(*) FROM goal_versions g2
                              WHERE g2.sprint_id = g.sprint_id AND g2.id <= g.id)
                 || ': ' || g.reason AS text
          FROM goal_versions g WHERE g.sprint_id = ${sid}''
        // {timeColumns = ["time"];};
    }
  ];

  panels = [
    (panel 1 "Goal" "stat" {
        x = 0;
        y = 0;
        w = 14;
        h = 5;
      } "table" "SELECT text FROM goal_current WHERE sprint_id = ${sid}"
      textStat)

    (panel 2 "Goal version" "stat" {
        x = 14;
        y = 0;
        w = 3;
        h = 5;
      } "table" "SELECT 'v' || versions FROM goal_current WHERE sprint_id = ${sid}"
      textStat)

    (panel 3 "Done" "stat" {
        x = 17;
        y = 0;
        w = 3;
        h = 5;
      } "table" "SELECT percent FROM progress WHERE sprint_id = ${sid}" {
        fieldConfig.defaults = {
          unit = "percent";
          min = 0;
          max = 100;
          color.mode = "thresholds";
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "text";
                value = null;
              }
              {
                color = "green";
                value = 100;
              }
            ];
          };
        };
        options = {
          reduceOptions.calcs = ["lastNotNull"];
          graphMode = "none";
          colorMode = "value";
        };
      })

    (panel 4 "Items" "stat" {
        x = 20;
        y = 0;
        w = 4;
        h = 5;
      } "table" ''
        SELECT done || ' of ' || in_scope
               || CASE WHEN dropped > 0 THEN ' · ' || dropped || ' dropped' ELSE ''' END
        FROM progress WHERE sprint_id = ${sid}''
      textStat)

    (panel 5 "Burn-up: done vs. in scope" "timeseries" {
        x = 0;
        y = 5;
        w = 16;
        h = 9;
      } "time series" ''
        SELECT time, in_scope AS "In scope", done AS "Done"
        FROM burnup WHERE sprint_id = ${sid} ORDER BY time'' {
        fieldConfig.defaults =
          line
          // {
            custom =
              line.custom
              // {
                lineInterpolation = "stepAfter";
              };
          };
        options.legend = {
          displayMode = "list";
          placement = "bottom";
        };
      })

    (panel 6 "Do now (you)" "table" {
        x = 16;
        y = 5;
        w = 8;
        h = 9;
      } "table" ''
        SELECT ROW_NUMBER() OVER (ORDER BY position) AS "#", title AS "Step", status AS "Status"
        FROM item_state
        WHERE sprint_id = ${sid} AND owner = 'user' AND status NOT IN ('done', 'dropped')
        ORDER BY position'' {
        fieldConfig.overrides = [(colorText "Status") (width "#" 40) (width "Status" 90)];
      })

    (panel 7 "Plan" "table" {
        x = 0;
        y = 14;
        w = 13;
        h = 10;
      } "table" ''
        SELECT item AS "#", title AS "Item", status AS "Status", owner AS "Owner",
               ${local "at"} AS "Updated", note AS "Note"
        FROM item_state WHERE sprint_id = ${sid} ORDER BY position'' {
        fieldConfig.overrides = [
          (colorText "Status")
          (width "#" 45)
          (width "Item" 220)
          (width "Status" 90)
          (width "Owner" 70)
          (width "Updated" 165)
        ];
      })

    (panel 8 "Pull requests" "table" {
        x = 13;
        y = 14;
        w = 11;
        h = 10;
      } "table" ''
        SELECT title AS "PR", state AS "State", ${local "at"} AS "Since", url AS "Link"
        FROM pr_state WHERE sprint_id = ${sid} ORDER BY at DESC'' {
        fieldConfig.overrides = [(colorText "State") (linkColumn "Link") (width "State" 110) (width "Since" 165)];
      })

    (panel 9 "PRs per day" "timeseries" {
        x = 0;
        y = 24;
        w = 12;
        h = 8;
      } "time series" ''
        SELECT (at / 86400) * 86400 AS time,
               SUM(state = 'opened') AS "Opened", SUM(state = 'merged') AS "Merged"
        FROM pr_events WHERE sprint_id = ${sid}
        GROUP BY at / 86400 ORDER BY time'' {
        fieldConfig.defaults = {
          custom = {
            drawStyle = "bars";
            fillOpacity = 80;
            lineWidth = 1;
            barAlignment = 0;
          };
          decimals = 0;
          min = 0;
        };
      })

    (panel 10 "Benchmarks" "timeseries" {
        x = 12;
        y = 24;
        w = 12;
        h = 8;
      } "time series" ''
        SELECT at AS time,
               suite || ' ' || metric || ' (' || unit || ')'
               || CASE WHEN is_baseline = 1 THEN ' baseline' ELSE ''' END AS series,
               value
        FROM bench_results WHERE sprint_id = ${sid} ORDER BY at'' {
        # The plugin splits rows into one series per text column value, as
        # a `series` label.
        fieldConfig = {
          defaults =
            line
            // {
              decimals = null;
              displayName = "\${__field.labels.series}";
            };
          overrides = [
            {
              matcher = {
                id = "byRegexp";
                options = ".*baseline.*";
              };
              properties = [
                {
                  id = "custom.lineStyle";
                  value = {
                    fill = "dash";
                    dash = [6 4];
                  };
                }
              ];
            }
          ];
        };
      })

    (panel 11 "Goal history" "table" {
        x = 0;
        y = 32;
        w = 12;
        h = 8;
      } "table" ''
        SELECT ${local "at"} AS "When", text AS "Goal", reason AS "Why", source AS "By"
        FROM goal_versions WHERE sprint_id = ${sid} ORDER BY at DESC, id DESC'' {
        fieldConfig.overrides = [(width "When" 165) (width "Goal" 240) (width "By" 60)];
      })

    (panel 12 "Decisions and steers" "table" {
        x = 12;
        y = 32;
        w = 12;
        h = 8;
      } "table" ''
        SELECT ${local "at"} AS "When", kind AS "Kind", text AS "What", link AS "Link"
        FROM log WHERE sprint_id = ${sid} ORDER BY at DESC, id DESC'' {
        fieldConfig.overrides = [(linkColumn "Link") (width "When" 165) (width "Kind" 80)];
      })

    (panel 13 "Benchmarks: latest vs baseline" "table" {
        x = 0;
        y = 40;
        w = 24;
        h = 10;
      } "table" ''
        WITH latest AS (
          SELECT suite, metric, unit, is_baseline, value,
                 ROW_NUMBER() OVER (PARTITION BY suite, metric, unit, is_baseline
                                    ORDER BY at DESC, id DESC) AS rn
          FROM bench_results WHERE sprint_id = ${sid}
        )
        SELECT suite AS "Suite", metric AS "Metric", unit AS "Unit",
               MAX(CASE WHEN is_baseline = 0 THEN value END) AS "Latest",
               MAX(CASE WHEN is_baseline = 1 THEN value END) AS "Baseline",
               ROUND(100.0 * (MAX(CASE WHEN is_baseline = 0 THEN value END)
                              - MAX(CASE WHEN is_baseline = 1 THEN value END))
                     / MAX(CASE WHEN is_baseline = 1 THEN value END), 1) AS "Change %"
        FROM latest WHERE rn = 1
        GROUP BY suite, metric, unit ORDER BY suite, metric'' {
        fieldConfig.overrides = [(width "Suite" 160) (width "Unit" 70)];
      })
  ];
}
