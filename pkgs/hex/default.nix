{upstreamHex}:
# The screenshot strings postdate the Russian table; upstream's coverage test fails.
upstreamHex.overrideAttrs (previous: {
  patches = (previous.patches or []) ++ [./russian-screenshots.patch];
})
