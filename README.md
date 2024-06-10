
# Peregrine
Peregrine is a tool for cleaning up and simplifying swift test output on the command line, to make it easier to find 
test failures, quickly

```sh
peregrine --help
```

> [!NOTE]
> peregrine is configured to output Nerd Font symbols by default. If you don't have a Nerd Font installed, you can:
> 1. [Install one!](https://www.nerdfonts.com/)
> 2. Pass the `--plain` flag to `peregrine run` for standard ascii-only output

## Known Issues
- Passing through the spm `--filter` or `--skip` flags causes the progress bar to behave unexpectedly - this is due to these flags not being respected by `swift test list`
- If peregrine crashes, the shell cursor may remain hidden. Run `tput cnorm` to fix
