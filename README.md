# Problem Statement

## Problem Description

Consider a graph \( G \) with \( |V| \) vertices and \( |E| \) edges organized in a level-order hierarchy. Vertices are numbered from \( 0 \) to \( |V|-1 \), and each vertex belongs to a specific level \( L \).

- **Graph Structure**:
  - Nodes are organized in \( L+1 \) levels (0 through \( L \)).
  - Each edge in the graph goes from a node in level \( L \) to a node in level \( L+1 \).
  - Vertices in level 0 have an activation point requirement (APR) of 0.
  - All other vertices \( v \) have \( APR[v] > 0 \).

- **Active In-Degree (AID)**:
  - AID of vertex \( v \) is the number of edges coming from active nodes (already activated) to vertex \( v \).

- **Activation Rule**:
  - If \( AID(v) \geq APR[v] \), vertex \( v \) becomes activated.

- **Deactivation Rule**:
  - If vertices \( (v-1) \) and \( (v+1) \) are inactive and all three vertices \( (v-1), v, (v+1) \) are on the same level, then \( v \) becomes inactive.

- **Initial State**:
  - Vertices in level 0 start as active (APR = 0).

- **Output**:
  - Print the number of active nodes in each level after processing, starting from level 0.
