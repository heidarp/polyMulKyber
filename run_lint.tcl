open_project spyglass.prj
if {![info exists ::env(SPYGLASS_GOAL)] || $::env(SPYGLASS_GOAL) eq ""} {
    set ::env(SPYGLASS_GOAL) lint/lint_rtl
}
run_goal $::env(SPYGLASS_GOAL)
exit -force
