# Show active warnings, then throw on failed assertions, otherwise return `value`.
#
# `assertions` and `warnings` are lists of `{ condition, message }`
# (see `assertions-warnings.nix`).
#
# This is a plain function rather than a `forge-lib` function, because
# `forge-lib` comes from the flake outputs and can't be used in `_module.check`.
{ lib }:
{ assertions, warnings }:
value:
let
  activeWarnings = lib.filter (x: x.condition) warnings;
  failedAssertions = lib.filter (x: !x.condition) assertions;
  assertionMessages = lib.concatMapStringsSep "\n" (x: "- ${x.message}") failedAssertions;

  checkedValue = lib.throwIf (
    failedAssertions != [ ]
  ) "\nFailed assertions:\n${assertionMessages}" value;
in
lib.foldr (w: acc: lib.warn w.message acc) checkedValue activeWarnings
