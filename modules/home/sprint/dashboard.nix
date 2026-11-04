# Sprint dashboard for Grafana, read from the `sprint` CLI's SQLite log.
# The views it reads (item_state, scoped_burnup, bench_summary, activity, ...)
# live in pkgs/sprint/store.go, so the SQL here stays short.
#
# Two variables pick what it shows: $sprint, and $subgoal ("-" is the whole
# sprint, any other value is one subgoal). Text panels use Business Text
# (marcusolsson-dynamictext-panel): Handlebars, then Markdown.
let
  ds = {
    type = "frser-sqlite-datasource";
    uid = "sprint-sqlite";
  };
  sid = "(SELECT id FROM sprints WHERE slug = '$sprint')";
  # Rows of the chosen scope: all rows for the whole sprint, else one subgoal's.
  inScope = col: "('$subgoal' = '-' OR ${col} = '$subgoal')";
  subgoalTitle = col: "COALESCE((SELECT g.title FROM subgoal_state g WHERE g.sprint_id = ${sid} AND g.key = ${col}), '')";
  # The end of the sprint's lines: the `end` entry, or now.
  endTime = "COALESCE((SELECT MAX(at) FROM log WHERE sprint_id = ${sid} AND kind = 'end'), CAST(strftime('%s', 'now') AS INTEGER))";

  # The plugin turns these columns (unix seconds) into times.
  target = queryType: sql: timeColumns: {
    refId = "A";
    datasource = ds;
    inherit queryType timeColumns;
    rawQueryText = sql;
    queryText = sql;
  };

  panel = id: title: type: gridPos: queryType: timeColumns: sql: extra:
    {
      inherit id title type gridPos;
      datasource = ds;
      targets = [(target queryType sql timeColumns)];
    }
    // extra;

  pos = x: y: w: h: {inherit x y w h;};

  # CSS for the text panels, scoped to the panel by the plugin. Grafana's
  # theme colors are not CSS variables, so neutrals use translucent grey
  # (fine on light and dark) and accents use Grafana's palette hues.
  textStyles = ''
    .dt-row { border-bottom: 0; padding: 2px 4px; }

    .hero .eyebrow { display: flex; align-items: center; gap: 8px; margin-bottom: 6px;
      font-size: 11px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; opacity: .7; }
    .hero .goal { font-size: 19px; line-height: 1.35; font-weight: 500; margin-bottom: 12px; }
    .callout { border-left: 3px solid #73BF69; background: rgba(115, 191, 105, .10);
      border-radius: 0 6px 6px 0; padding: 7px 12px; margin-bottom: 10px; line-height: 1.45; }
    .callout-label { font-size: 11px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase;
      color: #73BF69; margin-bottom: 2px; }
    .chip { display: inline-block; font-size: 11px; padding: 2px 8px; margin: 0 6px 4px 0;
      border-radius: 10px; background: rgba(128, 128, 128, .16); }
    .note { font-size: 12px; line-height: 1.45; opacity: .75; margin-top: 4px; }
    .pill { font-size: 10px; letter-spacing: .04em; padding: 1px 7px; border-radius: 9px;
      background: rgba(128, 128, 128, .2); }
    .pill-active { background: rgba(87, 148, 242, .22); color: #5794F2; }
    .pill-done { background: rgba(115, 191, 105, .22); color: #73BF69; }

    .ctx { --accent: #B877D9; margin: 0 0 12px; padding: 10px 14px 4px;
      border: 1px solid rgba(128, 128, 128, .22); border-left: 3px solid var(--accent);
      border-radius: 6px; background: rgba(128, 128, 128, .04); }
    .ctx-decision { --accent: #FF9830; background: rgba(255, 152, 48, .06); }
    .ctx-finding { --accent: #5794F2; }
    .ctx-risk { --accent: #F2495C; }
    .ctx-h { display: flex; justify-content: space-between; align-items: baseline; gap: 12px;
      margin-bottom: 8px; color: var(--accent);
      font-size: 12px; font-weight: 600; letter-spacing: .05em; text-transform: uppercase; }
    .ctx-h .when { color: rgb(128, 128, 128); font-size: 11px; font-weight: 400;
      letter-spacing: 0; text-transform: none; white-space: nowrap; }
    .ctx p { margin: 0 0 8px; line-height: 1.55; }
    .ctx ul, .ctx ol { margin: 0 0 8px; padding-left: 18px; }
    .ctx li { margin: 0 0 6px; padding-left: 2px; line-height: 1.5; }
    .ctx li::marker { color: var(--accent); }
    .ctx strong { font-weight: 600; }
    .ctx h1, .ctx h2, .ctx h3, .ctx h4 { margin: 12px 0 6px; font-size: 13px; font-weight: 600; }
    .ctx table { border-collapse: separate; border-spacing: 0; margin: 4px 0 10px; font-size: 12.5px;
      border: 1px solid rgba(128, 128, 128, .25); border-radius: 6px; overflow: hidden; }
    .ctx th, .ctx td { border: 0; border-bottom: 1px solid rgba(128, 128, 128, .18);
      padding: 5px 10px; text-align: left; vertical-align: top; }
    .ctx tr:last-child td { border-bottom: 0; }
    .ctx th { background: rgba(128, 128, 128, .12); font-weight: 600; }
    .ctx tbody tr:nth-child(even) td { background: rgba(128, 128, 128, .05); }
    .ctx code { font-size: .88em; padding: 1px 5px; border-radius: 4px; background: rgba(128, 128, 128, .16); }
    .ctx pre { padding: 8px 10px; border-radius: 6px; overflow: auto; background: rgba(128, 128, 128, .12); }
    .ctx pre code { padding: 0; background: none; }
    .ctx blockquote { margin: 4px 0 10px; padding: 6px 12px; border-left: 3px solid var(--accent);
      border-radius: 0 6px 6px 0; background: rgba(128, 128, 128, .08); }
    .ctx blockquote p { margin: 0; color: inherit; }
    .ctx a { text-decoration: none; border-bottom: 1px dotted; }
  '';

  text = renderMode: content: defaultContent: {
    options = {
      inherit renderMode content defaultContent;
      wrap = true;
      editors = [];
      helpers = "";
      afterRender = "";
      externalStyles = [];
      contentPartials = [];
      styles = textStyles;
    };
  };

  # Change against the baseline, in percent; lower is better.
  changeSteps = {
    mode = "absolute";
    steps = [
      {
        color = "green";
        value = null;
      }
      {
        color = "orange";
        value = 5;
      }
      {
        color = "red";
        value = 25;
      }
    ];
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
      active = {
        text = "active";
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
        text = "open";
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

  override = name: properties: {
    matcher = {
      id = "byName";
      options = name;
    };
    inherit properties;
  };
  colorText = name:
    override name [
      {
        id = "mappings";
        value = [statusColors];
      }
      {
        id = "custom.cellOptions";
        value = {type = "color-text";};
      }
    ];
  linkTo = name: url:
    override name [
      {
        id = "links";
        value = [
          {
            title = "Open";
            inherit url;
            targetBlank = true;
          }
        ];
      }
    ];
  hide = name:
    override name [
      {
        id = "custom.hidden";
        value = true;
      }
    ];
  width = name: px:
    override name [
      {
        id = "custom.width";
        value = px;
      }
    ];
  # Long text wraps in its cell instead of being cut off.
  wrapText = name:
    override name [
      {
        id = "custom.cellOptions";
        value = {
          type = "auto";
          wrapText = true;
        };
      }
    ];
  when = name:
    override name [
      {
        id = "unit";
        value = "time:DD MMM HH:mm";
      }
    ];

  table = overrides: {
    fieldConfig = {
      defaults.custom = {
        align = "auto";
        filterable = false;
      };
      inherit overrides;
    };
    options = {
      showHeader = true;
      cellHeight = "sm";
    };
  };

  line = {
    custom = {
      lineWidth = 2;
      fillOpacity = 0;
      showPoints = "always";
      pointSize = 5;
      spanNulls = true;
    };
  };

  # A subgoal's view: this dashboard with $subgoal set, same time range.
  subgoalLink = key: "/d/sprint/sprint?var-sprint=\${sprint}&var-subgoal=${key}&\${__url_time_range}";

  annotation = name: color: enable: sql: {
    inherit name enable;
    iconColor = color;
    datasource = ds;
    target = target "table" sql ["time"];
  };

  # Collapsed rows hold the long tables, so the top of the dashboard fits one screen.
  row = id: title: y: panels: {
    inherit id title panels;
    type = "row";
    collapsed = true;
    gridPos = pos 0 y 24 1;
  };
in {
  uid = "sprint";
  title = "Sprint";
  tags = ["sprint"];
  editable = false;
  graphTooltip = 1;
  refresh = "1m";
  schemaVersion = 39;
  time = {
    # `sprint show` links open at the sprint's start instead.
    from = "now-7d";
    to = "now";
  };

  templating.list = [
    {
      name = "sprint";
      label = "Sprint";
      type = "query";
      datasource = ds;
      query = "SELECT slug AS __value, title AS __text FROM sprints ORDER BY started_at DESC";
      refresh = 1;
      sort = 0;
    }
    {
      name = "subgoal";
      label = "View";
      type = "query";
      datasource = ds;
      # The plugin takes exactly two columns, so the order lives in a subquery.
      query = ''
        SELECT __value, __text FROM (
          SELECT '-' AS __value, 'Whole sprint' AS __text, -1e9 AS o
          UNION ALL
          SELECT key, 'Subgoal: ' || title || ' (' || status || ')', position
          FROM subgoal_state WHERE sprint_id = ${sid}
        ) ORDER BY o'';
      refresh = 1;
      sort = 0;
      current = {
        text = "Whole sprint";
        value = "-";
      };
    }
    {
      name = "suite";
      label = "Benchmark suites";
      type = "query";
      datasource = ds;
      query = "SELECT DISTINCT suite FROM bench_live WHERE sprint_id = ${sid} AND ${inScope "subgoal"} ORDER BY suite";
      refresh = 1;
      sort = 0;
      multi = true;
      includeAll = true;
      current = {
        text = ["All"];
        value = ["$__all"];
      };
    }
  ];

  annotations.list = [
    (annotation "Goal changes" "orange" true
      "SELECT at AS time, text FROM activity WHERE sprint_id = ${sid} AND kind = 'goal'")
    (annotation "Subgoal changes" "purple" true
      "SELECT at AS time, text FROM activity WHERE sprint_id = ${sid} AND kind = 'subgoal' AND ${inScope "subgoal"}")
    (annotation "Merges" "green" true
      "SELECT at AS time, 'Merged: ' || title AS text FROM pr_events WHERE sprint_id = ${sid} AND state = 'merged' AND ${inScope "subgoal"}")
    (annotation "Decisions" "blue" false
      "SELECT at AS time, text FROM log WHERE sprint_id = ${sid} AND kind IN ('decision', 'steer') AND ${inScope "subgoal"}")
  ];

  panels = [
    (panel 1 "Goal" "marcusolsson-dynamictext-panel" (pos 0 0 11 7) "table" [] ''
        SELECT 'Sprint goal · ' || s.title AS eyebrow, NULL AS status, g.text AS goal, NULL AS done_when,
               'Goal v' || g.versions AS version,
               'changed ' || strftime('%Y-%m-%d %H:%M', g.at, 'unixepoch', 'localtime') AS changed,
               CASE WHEN g.reason = 'sprint start' THEN NULL ELSE 'Why: ' || g.reason END AS note
        FROM sprints s JOIN goal_current g ON g.sprint_id = s.id
        WHERE s.id = ${sid} AND '$subgoal' = '-'
        UNION ALL
        SELECT 'Subgoal · ' || g.title, g.status, g.goal, g.done_when,
               (SELECT p.done || ' of ' || p.in_scope || ' items done' FROM subgoal_progress p
                WHERE p.sprint_id = g.sprint_id AND p.key = g.key),
               'changed ' || strftime('%Y-%m-%d %H:%M', g.at, 'unixepoch', 'localtime'),
               'Part of: ' || (SELECT text FROM goal_current WHERE sprint_id = ${sid})
        FROM subgoal_state g WHERE g.sprint_id = ${sid} AND g.key = '$subgoal' ''
      # One HTML block (no blank lines), so Markdown leaves it alone.
      (text "everyRow" ''
        <div class="hero">
        <div class="eyebrow">{{eyebrow}}{{#if status}}<span class="pill pill-{{status}}">{{status}}</span>{{/if}}</div>
        <div class="goal">{{goal}}</div>
        {{#if done_when}}
        <div class="callout"><div class="callout-label">Done when</div>{{done_when}}</div>
        {{/if}}
        <div><span class="chip">{{version}}</span><span class="chip">{{changed}}</span></div>
        {{#if note}}
        <div class="note">{{note}}</div>
        {{/if}}
        </div>
      '' "No sprint is selected."))

    (panel 2 "Progress" "stat" (pos 11 0 5 7) "table" [] ''
      SELECT percent AS "Done", done || ' of ' || in_scope AS "Items"
      FROM progress WHERE sprint_id = ${sid} AND '$subgoal' = '-'
      UNION ALL
      SELECT percent, done || ' of ' || in_scope
      FROM subgoal_progress WHERE sprint_id = ${sid} AND key = '$subgoal' '' {
      fieldConfig = {
        defaults = {
          color.mode = "fixed";
          color.fixedColor = "text";
        };
        overrides = [
          (override "Done" [
            {
              id = "unit";
              value = "percent";
            }
            {
              id = "color";
              value = {
                mode = "thresholds";
              };
            }
            {
              id = "thresholds";
              value = {
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
            }
          ])
        ];
      };
      options = {
        reduceOptions = {
          values = false;
          calcs = ["lastNotNull"];
          fields = "/.*/";
        };
        textMode = "value_and_name";
        colorMode = "value";
        graphMode = "none";
        justifyMode = "center";
        orientation = "horizontal";
      };
    })

    (panel 3 "Subgoals (click one to open it)" "bargauge" (pos 16 0 8 7) "table" [] ''
      SELECT g.title || ' · ' || g.status || ' · ' || p.done || '/' || p.in_scope AS label,
             p.percent AS "Done", g.key AS key
      FROM subgoal_state g
      JOIN subgoal_progress p ON p.sprint_id = g.sprint_id AND p.key = g.key
      WHERE g.sprint_id = ${sid} AND g.status != 'dropped'
      ORDER BY g.position'' {
      fieldConfig.defaults = {
        unit = "percent";
        min = 0;
        max = 100;
        displayName = "\${__data.fields.label}";
        color = {
          mode = "fixed";
          fixedColor = "blue";
        };
        links = [
          {
            title = "Open this subgoal";
            url = subgoalLink "\${__data.fields.key}";
          }
        ];
        noValue = "No subgoals";
      };
      options = {
        reduceOptions = {
          values = true;
          calcs = [];
          # Numeric fields only: the percent. (A name filter would see
          # each row's display name, not "Done".)
          fields = "";
        };
        displayMode = "basic";
        orientation = "horizontal";
        showUnfilled = true;
        valueMode = "color";
        namePlacement = "top";
        sizing = "auto";
      };
    })

    (panel 4 "Do now (you)" "table" (pos 0 7 9 9) "table" [] ''
      SELECT ROW_NUMBER() OVER (ORDER BY position) AS "#", title AS "Step", status AS "Status",
             ${subgoalTitle "subgoal"} AS "Subgoal"
      FROM item_state
      WHERE sprint_id = ${sid} AND owner = 'user' AND status NOT IN ('done', 'dropped')
        AND ${inScope "subgoal"}
      ORDER BY position''
    (table [(colorText "Status") (width "#" 36) (width "Status" 80) (width "Subgoal" 130) (wrapText "Step")]))

    (panel 5 "Burn-up: done vs. in scope" "timeseries" (pos 9 7 15 9) "time series" ["time"] ''
      SELECT time, in_scope AS "In scope", done AS "Done"
      FROM scoped_burnup WHERE sprint_id = ${sid} AND scope = '$subgoal'
      UNION ALL
      SELECT ${endTime}, in_scope, done FROM (
        SELECT in_scope, done FROM scoped_burnup
        WHERE sprint_id = ${sid} AND scope = '$subgoal' ORDER BY time DESC LIMIT 1)
      ORDER BY time'' {
      fieldConfig = {
        defaults =
          line
          // {
            custom =
              line.custom
              // {
                lineInterpolation = "stepAfter";
                showPoints = "never";
              };
            decimals = 0;
            min = 0;
          };
        overrides = [
          (override "In scope" [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = "text";
              };
            }
          ])
          (override "Done" [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = "blue";
              };
            }
            {
              id = "custom.fillOpacity";
              value = 15;
            }
          ])
        ];
      };
      options.legend = {
        displayMode = "list";
        placement = "bottom";
      };
    })

    (panel 6 "Context" "marcusolsson-dynamictext-panel" (pos 0 16 14 15) "table" [] ''
        SELECT title, body,
               strftime('%Y-%m-%d %H:%M', at, 'unixepoch', 'localtime') AS updated,
               CASE WHEN lower(title) LIKE '%decision%' THEN 'decision'
                    WHEN lower(title) LIKE '%finding%' THEN 'finding'
                    WHEN lower(title) LIKE '%risk%' OR lower(title) LIKE '%caveat%'
                      OR lower(title) LIKE '%not measured%' OR lower(title) LIKE '%open question%' THEN 'risk'
                    ELSE 'info' END AS kind
        FROM context_state
        WHERE sprint_id = ${sid}
          AND subgoal IS (CASE WHEN '$subgoal' = '-' THEN NULL ELSE '$subgoal' END)
        ORDER BY position, id''
      # Each section is a card: the <section> and header lines are HTML, and
      # the blank lines around the body let Markdown render it.
      (text "allRows" ''
        {{#each data}}
        <section class="ctx ctx-{{kind}}">
        <div class="ctx-h"><span>{{title}}</span><span class="when">updated {{updated}}</span></div>

        {{{body}}}

        </section>

        {{/each}}
      '' "No context sections yet. Agents add them with `sprint context set`."))

    # A table of (time, key, title, status), split into one row per subgoal by
    # the partitionByValues transformation. Each status lasts until the next.
    (panel 7 "Subgoal status over time" "state-timeline" (pos 14 16 10 5) "table" ["time"] ''
      SELECT e.at AS time, e.key AS key, g.title AS subgoal, e.status AS status
      FROM subgoal_events e JOIN subgoal_state g ON g.sprint_id = e.sprint_id AND g.key = e.key
      WHERE e.sprint_id = ${sid}
      UNION ALL
      SELECT ${endTime}, key, title, status FROM subgoal_state WHERE sprint_id = ${sid}
      ORDER BY time'' {
      transformations = [
        {
          id = "partitionByValues";
          options = {
            # By key, so two subgoals with one title keep two rows.
            fields = ["key" "subgoal"];
            keepFields = false;
            naming.asLabels = true;
          };
        }
      ];
      fieldConfig.defaults = {
        displayName = "\${__field.labels.subgoal}";
        color.mode = "fixed";
        mappings = [statusColors];
        custom = {
          fillOpacity = 70;
          lineWidth = 0;
        };
      };
      options = {
        showValue = "auto";
        mergeValues = true;
        rowHeight = 0.8;
        legend.showLegend = false;
      };
    })

    (panel 8 "Activity" "table" (pos 14 21 10 10) "table" ["When"] ''
        SELECT at AS "When", kind AS "Kind", text AS "What", link AS "Link"
        FROM activity WHERE sprint_id = ${sid} AND ${inScope "subgoal"}
        ORDER BY at DESC, id DESC LIMIT 300''
      (table [
        (when "When")
        (width "When" 105)
        (width "Kind" 70)
        (wrapText "What")
        (linkTo "What" "\${__data.fields.Link}")
        (hide "Link")
      ]))

    # One bar chart per suite: each metric's latest run beside its baseline.
    (panel 19 "\${suite}: latest run against baseline" "barchart" (pos 0 31 12 12) "table" [] ''
        SELECT metric || ' (' || unit || ')' AS "Metric", latest AS "Latest", baseline AS "Baseline"
        FROM bench_summary
        WHERE sprint_id = ${sid} AND ${inScope "subgoal"} AND suite IN (''${suite:sqlstring})
        ORDER BY COALESCE(latest, 0) - COALESCE(baseline, 0) DESC, metric'' {
      description = "Lower is better for times. The table below colours the change: green within 5% of the baseline or better, orange up to 25% worse, red more.";
      repeat = "suite";
      repeatDirection = "h";
      maxPerRow = 2;
      fieldConfig = {
        defaults = {
          color.mode = "fixed";
          custom = {
            fillOpacity = 85;
            lineWidth = 0;
            gradientMode = "none";
            axisSoftMin = 0;
            axisPlacement = "auto";
          };
        };
        overrides = [
          (override "Latest" [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = "#5794F2";
              };
            }
          ])
          (override "Baseline" [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = "#FF9830";
              };
            }
          ])
        ];
      };
      options = {
        orientation = "horizontal";
        xField = "Metric";
        showValue = "always";
        stacking = "none";
        groupWidth = 0.8;
        barWidth = 0.9;
        barRadius = 0.1;
        xTickLabelMaxLength = 40;
        legend = {
          showLegend = true;
          displayMode = "list";
          placement = "bottom";
        };
        tooltip.mode = "multi";
      };
    })

    (panel 9 "Benchmarks: latest run vs baseline" "table" (pos 0 43 14 14) "table" [] ''
        SELECT suite AS "Suite", metric AS "Metric", ${subgoalTitle "subgoal"} AS "Subgoal",
               latest AS "Latest", baseline AS "Baseline", unit AS "Unit", change AS "Change %",
               runs AS "Runs"
        FROM bench_summary
        WHERE sprint_id = ${sid} AND ${inScope "subgoal"} AND suite IN (''${suite:sqlstring})
        ORDER BY subgoal, suite, metric''
      (table [
        (width "Suite" 170)
        (width "Subgoal" 110)
        (width "Latest" 65)
        (width "Baseline" 70)
        (width "Unit" 45)
        (width "Change %" 75)
        (width "Runs" 45)
        (width "Metric" 110)
        (wrapText "Metric")
        (override "Change %" [
          {
            id = "decimals";
            value = 1;
          }
          {
            id = "custom.cellOptions";
            value = {type = "color-background";};
          }
          {
            id = "thresholds";
            value = changeSteps;
          }
          {
            id = "color";
            value.mode = "thresholds";
          }
          {
            id = "mappings";
            value = [
              {
                type = "special";
                options = {
                  match = "null";
                  result = {
                    text = "no baseline";
                    color = "transparent";
                  };
                };
              }
            ];
          }
        ])
      ]))

    (panel 20 "Benchmarks at most 5% worse than baseline" "stat" (pos 14 43 10 3) "table" [] ''
        SELECT SUM(change <= 5) || ' of ' || COUNT(*) AS "Within 5%"
        FROM bench_summary
        WHERE sprint_id = ${sid} AND ${inScope "subgoal"} AND suite IN (''${suite:sqlstring})
          AND change IS NOT NULL'' {
      description = "Benchmarks with both a latest run and a baseline. Lower is better.";
      options = {
        textMode = "value";
        colorMode = "none";
        graphMode = "none";
        reduceOptions = {
          values = true;
          calcs = [];
          fields = "/.*/";
        };
      };
    })

    (panel 21 "Change against baseline, worst first (%)" "bargauge" (pos 14 46 10 11) "table" [] ''
        SELECT suite || ' · ' || metric AS "Metric", change AS "Change"
        FROM bench_summary
        WHERE sprint_id = ${sid} AND ${inScope "subgoal"} AND suite IN (''${suite:sqlstring})
          AND change IS NOT NULL
        ORDER BY change DESC'' {
      fieldConfig.defaults = {
        unit = "percent";
        decimals = 0;
        # Clipped, so one outlier doesn't flatten the other bars.
        min = -50;
        max = 200;
        displayName = "\${__data.fields.Metric}";
        color.mode = "thresholds";
        thresholds = changeSteps;
      };
      options = {
        orientation = "horizontal";
        displayMode = "basic";
        valueMode = "color";
        showUnfilled = true;
        namePlacement = "left";
        minVizHeight = 14;
        maxVizHeight = 22;
        reduceOptions = {
          values = true;
          calcs = [];
          fields = "";
        };
      };
    })

    (row 22 "Benchmarks over time" 57 [
      (panel 10 "Benchmarks over time" "timeseries" (pos 0 58 24 10) "time series" ["time"] ''
        SELECT at AS time,
               suite || ' ' || metric || ' (' || unit || ')'
               || CASE WHEN '$subgoal' = '-' THEN ' · ' || COALESCE(subgoal, 'whole sprint') ELSE ''' END
               || CASE WHEN is_baseline = 1 THEN ' baseline' ELSE ''' END AS series,
               value
        FROM bench_live
        WHERE sprint_id = ${sid} AND ${inScope "subgoal"} AND suite IN (''${suite:sqlstring})
        ORDER BY at'' {
        # The plugin splits rows into one series per value of the text
        # column, as a `series` label.
        fieldConfig = {
          defaults =
            line
            // {
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
        options = {
          legend = {
            displayMode = "list";
            placement = "bottom";
          };
          tooltip.mode = "multi";
        };
      })

    ])

    (row 11 "Plan: every item" 65 [
      (panel 12 "Items" "table" (pos 0 66 24 14) "table" ["Updated"] ''
          SELECT item AS "#", title AS "Item", status AS "Status", owner AS "Owner",
                 ${subgoalTitle "subgoal"} AS "Subgoal", at AS "Updated", note AS "Note"
          FROM item_state WHERE sprint_id = ${sid} AND ${inScope "subgoal"} ORDER BY position''
        (table [
          (colorText "Status")
          (when "Updated")
          (width "#" 45)
          (width "Status" 80)
          (width "Owner" 65)
          (width "Updated" 105)
          (width "Subgoal" 150)
          (wrapText "Item")
          (wrapText "Note")
        ]))
    ])

    (row 13 "Pull requests" 66 [
      (panel 14 "Pull requests" "table" (pos 0 67 24 12) "table" ["Since"] ''
          SELECT title AS "PR", state AS "State", ${subgoalTitle "subgoal"} AS "Subgoal",
                 at AS "Since", url AS "Link"
          FROM pr_state WHERE sprint_id = ${sid} AND ${inScope "subgoal"} ORDER BY at DESC''
        (table [
          (colorText "State")
          (when "Since")
          (linkTo "PR" "\${__data.fields.Link}")
          (hide "Link")
          (width "State" 100)
          (width "Since" 105)
          (width "Subgoal" 150)
        ]))
    ])

    (row 15 "History: goal, subgoals, context sections" 67 [
      (panel 16 "Goal versions" "table" (pos 0 68 12 9) "table" ["When"] ''
        SELECT at AS "When", text AS "Goal", reason AS "Why", source AS "By"
        FROM goal_versions WHERE sprint_id = ${sid} ORDER BY at DESC, id DESC''
      (table [(when "When") (width "When" 105) (width "By" 55) (wrapText "Goal") (wrapText "Why")]))
      (panel 17 "Subgoal changes" "table" (pos 12 68 12 9) "table" ["When"] ''
        SELECT at AS "When", title AS "Subgoal", status AS "Status", goal AS "Goal",
               done_when AS "Done when", reason AS "Why"
        FROM subgoal_events WHERE sprint_id = ${sid} AND ${inScope "key"} ORDER BY at DESC, id DESC''
      (table [(when "When") (colorText "Status") (width "When" 105) (width "Status" 70) (wrapText "Goal") (wrapText "Done when") (wrapText "Why")]))
      (panel 18 "Context section versions (open a cell to read it)" "table" (pos 0 77 24 10) "table" ["When"] ''
        SELECT at AS "When", ${subgoalTitle "subgoal"} AS "Subgoal", title AS "Section",
               CASE WHEN body = ''' THEN '(removed)' ELSE body END AS "Text"
        FROM context_versions
        WHERE sprint_id = ${sid}
          AND ('$subgoal' = '-' OR subgoal = '$subgoal')
        ORDER BY at DESC, id DESC''
      (table [(when "When") (width "When" 105) (width "Subgoal" 150) (width "Section" 180)]))
    ])
  ];
}
