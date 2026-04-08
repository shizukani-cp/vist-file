# vist-file.nvim

A file system adapter for `vist.nvim` that brings oil.nvim-like editing capabilities to Neovim.

## Overview

`vist-file` transforms your buffer into an interactive file manager.
By utilizing the `vist.nvim` engine, it maps standard text editing operations directly to file system actions.

## Features

- **Intuitive Editing**: Create, rename, or delete files and directories by simply editing lines in the buffer.

- **Protocol-based Navigation**: Uses `vist-file://` to manage directory contexts.

- **Safe Operations**: All destructive actions require explicit confirmation via a unified diff-like dialog.

- **Devicon Support**: Automatic icon rendering for files and directories.

## Installation

Using lazy.nvim:

```lua
{
    "shizukani-cp/vist-file.nvim",
    dependencies = {
        "shizukani-cp/vist.nvim",
        "nvim-tree/nvim-web-devicons"
    }
}
```

## Keymaps

Within a `vist-file` buffer:


|Key|Action|
|---|---|
|`<CR>`|Open file or enter directory|
|`-`|Move to parent directory|
|`:w`|Parse changes and apply to file system|

## Usage

```lua
local vist = require("vist.core")
local file_adapter = require("vist.adapters.file")

vist.open(file_adapter)
```
