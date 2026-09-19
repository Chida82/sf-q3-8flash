# Distributed execution

The transport, TP/RDMA, and pipeline interfaces are retained as a StarForge
invariant, together with their model-less tests. The current Qwen3.8 runtime
rejects distributed graph execution because its recurrent state, n-gram reads,
and MTP state do not yet have a verified partitioning contract.

Do not remove `ds4_tp.*`, `ds4_distributed.*`, or their tests. A Qwen
distributed implementation must define state ownership and synchronization,
add focused transport/state tests, run on the intended machines, and pass the
upstream parity oracle before the restriction is lifted.
