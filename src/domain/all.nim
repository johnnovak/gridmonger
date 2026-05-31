# domain/all
#
# Aggregator that re-exports every module in src/domain/. Consumers outside
# the domain folder can `import domain/all` instead of listing the 7
# individual modules. Files inside domain/ keep their explicit imports —
# they need to declare which sibling they actually depend on, and an
# aggregator import here would create a cycle.
# Side effects: none (pure data model).

import ./annotations
import ./cellgrid
import ./level
import ./links
import ./map
import ./regions
import ./selection

export annotations
export cellgrid
export level
export links
export map
export regions
export selection

# vim: et:ts=2:sw=2:fdm=marker
