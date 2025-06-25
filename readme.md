# Zonk

Zonk is a superset of [BrainF](https://en.wikipedia.org/wiki/Brainfuck), made to be an easier compilation target than vanilla BrainF.

## Operations

The original eight BrainF operations are:

Operation | Description
--------- | -----------
`>` | Incrememt the data pointer by one.
`<` | Decrement the data pointer by one.
`+` | Incrememt the current cell by one.
`-` | Decrement the current cell by one.
`.` | Print the value of the current cell as an ASCII character.
`,` | Ask for one byte of input and set the current cell to it.
`[` | If the current cell is zero, jump to the position after the corresponding `]`.
`]` | If the current cell is zero, jump to the position after the corresponding `]`.

Along with those, Zonk adds 7 extra operations:

Operation | Description
--------- | -----------
`_` | Copy the value of the current cell into the cell to the right.
`/` | Jump forward by the amount specified by the current cell.
`\` | Jump back by the amount specified by the current cell.
`{[path, excluding extension]}`, e.g. `{/libs/io}` | Loads a dynamic library.
`$[name]` | Switches to the context to the specified module.
`@[name]` | Looks up the specified function in the context then calls it.
