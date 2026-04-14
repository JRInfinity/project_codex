# Software Layout

Recommended software-side organization:

- `sw/include/`: register definitions and shared headers
- `sw/examples/`: bring-up and demo programs
- `sw/scripts/`: helper scripts such as Q16 coefficient generators

This keeps register programming examples separate from RTL and simulation files.
