import Vos.Kernel
import Vos.Queue
import Vos.Sched
import Vos.Spec.Queue

-- `scripts/check-axioms.sh` rejects an incomplete proof and any axiom other than
-- `propext`, `Classical.choice`, and `Quot.sound`.
#print axioms Vos.Spec.Queue.enq_accept
#print axioms Vos.Spec.Queue.enq_reject
#print axioms Vos.Spec.Queue.enq_prefix
#print axioms Vos.Spec.Queue.deq_head
#print axioms Vos.Spec.Queue.pushAll_append
#print axioms Vos.Spec.Queue.fifo
#print axioms Vos.Queue.length_le
#print axioms Vos.Sched.empty_inv
#print axioms Vos.Sched.ready_bounded
#print axioms Vos.Sched.blocked_not_current
#print axioms Vos.Sched.dispatch_inv
#print axioms Vos.Sched.dispatch_not_blocked
#print axioms Vos.Sched.priority_max
#print axioms Vos.Sched.coop_yield_runs_head
#print axioms Vos.Sched.delay_blocks
#print axioms Vos.Sched.ticks_before_deadline
#print axioms Vos.Sched.spawn_inv
#print axioms Vos.Sched.yield_inv
#print axioms Vos.Sched.block_inv
#print axioms Vos.Sched.unblock_inv
#print axioms Vos.Sched.delay_inv
#print axioms Vos.Sched.exit_inv
#print axioms Vos.Sched.wakeDue_inv
#print axioms Vos.Sched.tick_inv
#print axioms Vos.Kernel.send_room
#print axioms Vos.Kernel.send_to_waiter
#print axioms Vos.Kernel.send_full
#print axioms Vos.Kernel.recv_head
#print axioms Vos.Kernel.recv_empty
