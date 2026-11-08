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
  # Live items (`sprint live`, `sprint poll`): live.db beside the log.
  liveItemsDs = {
    type = "frser-sqlite-datasource";
    uid = "sprint-live";
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

  # Active stages first, done ones last.
  stageOrder = "CASE g.status WHEN 'active' THEN 0 WHEN 'done' THEN 2 ELSE 1 END";

  # One section of the static status page as a Business Text panel. Its
  # queries get refIds A, B, ...; ./page/prelude.js and ./page/<name>.js
  # build the HTML from them, and ./page/page.css styles it. pagePanelFrom
  # reads another datasource.
  pagePanelFrom = source: id: name: gridPos: sqls: {
    inherit id gridPos;
    title = "";
    type = "marcusolsson-dynamictext-panel";
    transparent = true;
    datasource = source;
    targets =
      builtins.genList
      (i:
        target "table" (builtins.elemAt sqls i) []
        // {
          refId = builtins.elemAt ["A" "B" "C" "D"] i;
          datasource = source;
        })
      (builtins.length sqls);
    options = {
      renderMode = "data";
      content = "{{{html}}}";
      defaultContent = "{{{html}}}";
      wrap = true;
      editors = [];
      helpers = "const panelName = '${name}';\n" + builtins.readFile ./page/prelude.js + "\n" + builtins.readFile (./page + "/${name}.js");
      # Folds what doesn't fit the panel, so no section scrolls on its own.
      afterRender = builtins.readFile ./page/fit.js;
      externalStyles = [];
      contentPartials = [];
      styles = builtins.readFile ./page/page.css;
    };
  };
  pagePanel = pagePanelFrom ds;
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
    # `sprint dash dev` sets this to the checkout's branch@sha. The header
    # shows it, so a dev copy is never mistaken for the switched one.
    {
      name = "dev";
      type = "constant";
      query = "";
      hide = 2;
    }
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
    # The static status page, section by section. Each panel runs its SQL
    # (refId A, B, ...) and a builder from ./page, which writes the HTML.
    (pagePanel 31 "header" (pos 0 0 17 5) [
      "SELECT s.title, g.text AS goal, g.versions, g.at FROM sprints s JOIN goal_current g ON g.sprint_id = s.id WHERE s.id = ${sid}"
      "SELECT title, status, goal, done_when FROM subgoal_state WHERE sprint_id = ${sid} AND key = '$subgoal'"
    ])
    (pagePanel 32 "progress" (pos 17 0 7 5) [
      ''
        SELECT percent, done, in_scope FROM progress WHERE sprint_id = ${sid} AND '$subgoal' = '-'
        UNION ALL
        SELECT percent, done, in_scope FROM subgoal_progress WHERE sprint_id = ${sid} AND key = '$subgoal' ''
    ])
    # Live items for this view: a subgoal's view shows its own items and the
    # whole sprint's. A done item stays for an hour. A background chore
    # (`sprint poll --background`) shows only when it fails or goes stale. Anything a sprint polls
    # (benchmarks, CI, deploys) shows here, so no panel is sprint-specific.
    (pagePanelFrom liveItemsDs 44 "live" (pos 0 5 24 8) [
      ''
        SELECT key, subgoal, title, body, done_n, total_n, ends_at, stale_after, link, state, error,
               updated_at, seen_at, done_at
        FROM live_items
        WHERE sprint = '$sprint' AND (subgoal IS NULL OR ${inScope "subgoal"})
          AND (state = 'live' OR done_at > CAST(strftime('%s', 'now') AS INTEGER) - 3600)
          -- A background chore shows only when it fails or goes stale.
          AND (background = 0 OR error IS NOT NULL
               OR (stale_after IS NOT NULL AND seen_at < CAST(strftime('%s', 'now') AS INTEGER) - stale_after))
        ORDER BY state = 'done', created_at, key''
    ])
    # The sprint's do_now list, filtered: a subgoal's view keeps the sprint's
    # step numbers and shows the steps without a subgoal too.
    (pagePanel 33 "donow" (pos 0 13 10 15) [
      ''
        SELECT item, title, status, note, stage, state, rank, total, '$subgoal' != '-' AS filtered
        FROM do_now
        WHERE sprint_id = ${sid} AND (subgoal IS NULL OR ${inScope "subgoal"})
        ORDER BY rank''
      # The steps this view hides: a stage view must say they exist (6 Nov).
      ''
        SELECT COUNT(*) AS n, COALESCE(SUM(state = 'ready'), 0) AS ready
        FROM do_now
        WHERE sprint_id = ${sid} AND NOT COALESCE(subgoal IS NULL OR ${inScope "subgoal"}, 0)''
    ])
    (pagePanel 34 "stages" (pos 10 13 14 15) [
      ''
        SELECT g.key, g.title, g.status, g.done_when, p.done, p.in_scope, p.percent
        FROM subgoal_state g JOIN subgoal_progress p ON p.sprint_id = g.sprint_id AND p.key = g.key
        WHERE g.sprint_id = ${sid} AND g.status != 'dropped'
        ORDER BY ${stageOrder}, g.position''
    ])
    # Chains of the user's steps linked by needs, for the steps Do now leaves
    # out because the user can't act on them yet. Same scope as Do now.
    (pagePanel 46 "timeline" (pos 0 28 24 24) [
      ''
        SELECT item, title, stage, waits_on, needs, note, state, rank, at
        FROM timeline
        WHERE sprint_id = ${sid} AND (subgoal IS NULL OR ${inScope "subgoal"})
        ORDER BY item''
    ])
    # Open PRs, sorted by what to do next, from the log: `sprint pr sync`
    # writes each PR's board row (pr_review_state), so no generator runs.
    (pagePanel 45 "prs" (pos 0 52 24 12) [
      ''
        SELECT p.url, p.title, p.state, p.at, COALESCE(g.title, ''') AS stage,
               r.number, r.head, r.base, r.draft, r.failing, r.running, r.threads, r.bots,
               r.grp, r.steps, r.rank, r.why, r.stack, COALESCE(n.text, ''') AS note,
               -- No stage while the sprint has stages: `sprint pr set` gives it one.
               p.subgoal IS NULL AND EXISTS (SELECT 1 FROM subgoal_state s
                                             WHERE s.sprint_id = p.sprint_id AND s.status != 'dropped') AS unstaged
        FROM pr_state p
        LEFT JOIN pr_review_state r ON r.sprint_id = p.sprint_id AND r.url = p.url
        LEFT JOIN subgoal_state g ON g.sprint_id = p.sprint_id AND g.key = p.subgoal
        LEFT JOIN pr_note_state n ON n.sprint_id = p.sprint_id AND n.url = p.url
        WHERE p.sprint_id = ${sid} AND ${inScope "p.subgoal"}
          AND (p.state IN ('opened', 'ready')
               OR (p.state = 'merged' AND p.at > CAST(strftime('%s', 'now') AS INTEGER) - 3 * 86400))
        ORDER BY p.state = 'merged', CASE WHEN p.state != 'merged' THEN COALESCE(r.rank, 1e9) END, p.at DESC''
      "SELECT MAX(at) AS at FROM pr_syncs WHERE sprint_id = ${sid}"
      # Merge-ready PRs this view's stage filter hides (6 Nov: #18417 was in
      # another stage and the reader missed it).
      ''
        SELECT COUNT(*) AS n
        FROM pr_state p
        JOIN pr_review_state r ON r.sprint_id = p.sprint_id AND r.url = p.url
        WHERE p.sprint_id = ${sid} AND p.state IN ('opened', 'ready') AND r.grp = 'merge'
          AND NOT COALESCE(${inScope "p.subgoal"}, 0)''
    ])
    # What is left comes before the context sections: Chun reads the open
    # steps first (6 Nov).
    (pagePanel 36 "left" (pos 0 64 24 14) [
      ''
        SELECT g.key, g.title, g.status, g.goal
        FROM subgoal_state g
        WHERE g.sprint_id = ${sid} AND g.status != 'dropped' AND ${inScope "g.key"}
        ORDER BY ${stageOrder}, g.position''
      ''
        SELECT item, title, owner, status, note, subgoal FROM item_state
        WHERE sprint_id = ${sid} AND status NOT IN ('done', 'dropped') AND ${inScope "subgoal"}
        ORDER BY position''
      ''
        SELECT subgoal, title, body, at FROM context_state
        WHERE sprint_id = ${sid} AND subgoal IS NOT NULL AND body != ''' AND ${inScope "subgoal"}
        ORDER BY position, id''
    ])
    (pagePanel 35 "context" (pos 0 78 24 10) [
      "SELECT title, body, at FROM context_state WHERE sprint_id = ${sid} AND subgoal IS NULL AND body != '' ORDER BY position, id"
    ])
    (pagePanel 37 "bench" (pos 0 88 24 9) [
      ''
        SELECT suite, metric, unit, latest, baseline, change, ${subgoalTitle "subgoal"} AS stage
        FROM bench_summary
        WHERE sprint_id = ${sid} AND ${inScope "subgoal"} AND suite IN (''${suite:sqlstring})
        ORDER BY suite, COALESCE(change, -1e9) DESC''
    ])

    (row 39 "Charts: burn-up, stage status over time, activity" 97 [
      (panel 5 "Burn-up: done vs. in scope" "timeseries" (pos 0 87 14 9) "time series" ["time"] ''
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
      # A table of (time, key, title, status), split into one row per subgoal by
      # the partitionByValues transformation. Each status lasts until the next.
      (panel 7 "Subgoal status over time" "state-timeline" (pos 14 87 10 9) "table" ["time"] ''
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
      (panel 8 "Activity" "table" (pos 0 96 24 10) "table" ["When"] ''
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
    ])

    (row 22 "Benchmark charts" 98 [
      # One bar chart per suite: each metric's latest run beside its baseline.
      (panel 19 "\${suite}: latest run against baseline" "barchart" (pos 0 89 12 12) "table" [] ''
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
      (panel 9 "Benchmarks: latest run vs baseline" "table" (pos 0 101 14 14) "table" [] ''
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
      (panel 20 "Benchmarks at most 5% worse than baseline" "stat" (pos 14 101 10 3) "table" [] ''
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
      (panel 21 "Change against baseline, worst first (%)" "bargauge" (pos 14 104 10 11) "table" [] ''
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
      (panel 10 "Benchmarks over time" "timeseries" (pos 0 115 24 10) "time series" ["time"] ''
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

    (row 11 "Plan: every item" 99 [
      (panel 12 "Items" "table" (pos 0 98 24 14) "table" ["Updated"] ''
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

    (row 13 "Pull requests" 100 [
      (panel 14 "Pull requests" "table" (pos 0 99 24 12) "table" ["Since"] ''
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

    (row 15 "History: goal, subgoals, context sections" 101 [
      (panel 16 "Goal versions" "table" (pos 0 100 12 9) "table" ["When"] ''
        SELECT at AS "When", text AS "Goal", reason AS "Why", source AS "By"
        FROM goal_versions WHERE sprint_id = ${sid} ORDER BY at DESC, id DESC''
      (table [(when "When") (width "When" 105) (width "By" 55) (wrapText "Goal") (wrapText "Why")]))
      (panel 17 "Subgoal changes" "table" (pos 12 100 12 9) "table" ["When"] ''
        SELECT at AS "When", title AS "Subgoal", status AS "Status", goal AS "Goal",
               done_when AS "Done when", reason AS "Why"
        FROM subgoal_events WHERE sprint_id = ${sid} AND ${inScope "key"} ORDER BY at DESC, id DESC''
      (table [(when "When") (colorText "Status") (width "When" 105) (width "Status" 70) (wrapText "Goal") (wrapText "Done when") (wrapText "Why")]))
      (panel 18 "Context section versions (open a cell to read it)" "table" (pos 0 109 24 10) "table" ["When"] ''
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
